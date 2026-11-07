"""Boundary checks for the complete native source, using synthetic homes only."""

import json
import os
from pathlib import Path
import tomllib
import unittest

from chezmoi_source_support import AI_MUTABLE, SourceFixture, expected_entries, snapshot


HOST = "win" if os.name == "nt" else "common-only"
LIVE = {
    ".claude/settings.json": b'{"model":"fixture-local","fixture_live":{"keep":false}}\n',
    ".codex/config.toml": b'model = "fixture-local"\n[fixture_live]\nkeep = false\n',
}
UNMANAGED = {
    ".secrets/unmanaged": b"fixture unrelated private state\n",
    ".claude/session-state.json": b'{"fixture":"app-written"}\n',
    ".codex/auth.json": b'{"fixture":"app-written"}\n',
    ".codex/rules/default.rules": b"fixture local policy\n",
}
POISONS = ("python3", "python", "jq", "node", "sh", "bash", "pwsh")


def poison_interpreters(directory, calls):
    # Each poison records its name in CALLS (an absolute path that may contain
    # spaces) and fails, so any interpreter a native transform starts is seen.
    for name in POISONS:
        if os.name == "nt":
            (directory / f"{name}.cmd").write_text(
                f'@echo {name}>>"{calls}"\r\n@exit /b 97\r\n', encoding="utf-8", newline="")
        else:
            poison = directory / name
            poison.write_text(f"#!/bin/sh\nprintf '%s\\n' {name} >>\"{calls}\"\nexit 97\n",
                              encoding="utf-8")
            poison.chmod(0o755)


class NativeIntegrationTests(unittest.TestCase):
    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def seed_live(self, fixture):
        for name, content in {**LIVE, **UNMANAGED}.items():
            target = fixture.destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            if os.name != "nt":
                target.chmod(0o600)

    def require_mutable_targets(self, fixture):
        # Otherwise a missing template could make a refusal test pass vacuously.
        result = fixture.run("managed", "--include=files", "--nul-path-separator")
        self.assert_success(result)
        managed = {path.replace("\\", "/") for path in result.stdout.split("\0") if path}
        self.assertTrue(AI_MUTABLE <= managed, f"missing native targets: {AI_MUTABLE - managed}")

    def assert_target_refused(self, fixture, name):
        # Apply only the affected target: this is not an all-home transaction.
        self.require_mutable_targets(fixture)
        source = snapshot(fixture.source)
        destination = snapshot(fixture.destination)
        target = fixture.destination / name
        mode = target.stat().st_mode
        result = fixture.run("apply", str(target))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(target.stat().st_mode, mode)
        self.assertEqual(snapshot(fixture.destination), destination)
        self.assertEqual(snapshot(fixture.source), source)

    def test_complete_apply_without_external_merge_dependencies(self):
        # Native transforms never shell out: every interpreter on the child PATH is a poison.
        with SourceFixture(HOST) as fixture:
            self.seed_live(fixture)
            self.assertEqual(list(Path(fixture.env["PATH"]).iterdir()), [])
            calls = fixture.root / "interpreter calls"
            poison_interpreters(Path(fixture.env["PATH"]), calls)
            source = snapshot(fixture.source)
            self.assert_success(fixture.run("apply"))
            self.assertFalse(calls.exists(), calls.read_text(encoding="utf-8") if calls.exists() else "")
            for name in AI_MUTABLE:
                with self.subTest(target=name):
                    target = fixture.destination / name
                    self.assertTrue(target.is_file(), f"native mutable target missing: {name}")
                    parse = json.loads if name.endswith(".json") else tomllib.loads
                    actual = parse(target.read_text(encoding="utf-8"))
                    portable = fixture.source / expected_entries(HOST)[name].source
                    wanted = parse(portable.read_text(encoding="utf-8"))
                    wanted["fixture_live"] = {"keep": False}
                    if name.endswith(".json"):
                        wanted["model"] = "fixture-local"
                    self.assertEqual(actual, wanted)
            for name, content in UNMANAGED.items():
                self.assertEqual((fixture.destination / name).read_bytes(), content)
            self.assertEqual(snapshot(fixture.source), source)

    def test_malformed_live_preserves_affected_file_and_unmanaged_siblings(self):
        for name, malformed in ((".claude/settings.json", b'{"fixture":\r\n'),
                                (".codex/config.toml", b'[fixture\r\n')):
            with self.subTest(target=name), SourceFixture(HOST) as fixture:
                self.seed_live(fixture)
                (fixture.destination / name).write_bytes(malformed)
                self.assert_target_refused(fixture, name)

    def test_malformed_portable_preserves_affected_file_and_source(self):
        for name, malformed in ((".claude/settings.json", b'{"permissions":'),
                                (".codex/config.toml", b'model = [\n')):
            with self.subTest(target=name), SourceFixture(HOST) as fixture:
                self.seed_live(fixture)
                portable = fixture.source / expected_entries(HOST)[name].source
                portable.write_bytes(malformed)
                self.assert_target_refused(fixture, name)

    def test_target_directory_conflict_preserves_directory_contents_and_mode(self):
        for name in sorted(AI_MUTABLE):
            with self.subTest(target=name), SourceFixture(HOST) as fixture:
                self.seed_live(fixture)
                target = fixture.destination / name
                target.unlink()
                target.mkdir()
                if os.name != "nt":
                    target.chmod(0o700)
                (target / "fixture-unmanaged").write_bytes(b"directory conflict survivor\n")
                self.assert_target_refused(fixture, name)
                self.assertTrue(target.is_dir())

    def test_portable_policy_is_included_literally_without_template_evaluation(self):
        # includeTemplate would evaluate these valid policy strings and abort.
        marker = '{{ fail "fixture policy must remain literal" }}'
        with SourceFixture(HOST) as fixture:
            self.seed_live(fixture)
            entries = expected_entries(HOST)
            claude = fixture.source / entries[".claude/settings.json"].source
            policy = json.loads(claude.read_bytes())
            policy["fixture_literal"] = marker
            claude.write_bytes((json.dumps(policy) + "\n").encode("utf-8"))
            codex = fixture.source / entries[".codex/config.toml"].source
            text = codex.read_text(encoding="utf-8")
            old = tomllib.loads(text)["permissions"]["workspace-net"]["description"]
            codex.write_bytes(text.replace(json.dumps(old), json.dumps(marker), 1).encode("utf-8"))
            source = snapshot(fixture.source)
            self.assert_success(fixture.run("apply"))
            self.require_mutable_targets(fixture)
            claude_live = json.loads((fixture.destination / ".claude/settings.json").read_bytes())
            codex_live = tomllib.loads((fixture.destination / ".codex/config.toml").read_text(encoding="utf-8"))
            self.assertEqual(claude_live["fixture_literal"], marker)
            self.assertEqual(codex_live["permissions"]["workspace-net"]["description"], marker)
            self.assertEqual(snapshot(fixture.source), source)

    def test_apply_leaves_polluted_portable_source_unchanged(self):
        # Polluted portable input stays untouched; unknown Codex fields gain no ownership.
        with SourceFixture(HOST) as fixture:
            self.seed_live(fixture)
            codex = fixture.source / expected_entries(HOST)[".codex/config.toml"].source
            with codex.open("ab") as stream:
                stream.write(b'\n[fixture_portable_only]\nvalue = "keep source unchanged"\n')
            source = snapshot(fixture.source)
            self.assert_success(fixture.run("apply"))
            self.require_mutable_targets(fixture)
            actual = tomllib.loads((fixture.destination / ".codex/config.toml").read_text(encoding="utf-8"))
            self.assertNotIn("fixture_portable_only", actual)
            self.assertEqual(actual["fixture_live"], {"keep": False})
            self.assertEqual(snapshot(fixture.source), source)


if __name__ == "__main__":
    unittest.main()
