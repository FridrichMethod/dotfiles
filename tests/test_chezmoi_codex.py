"""Native Codex ownership and TOML safety, using only disposable native homes."""

import importlib.util
import json
import os
from pathlib import Path
import tomllib
import unittest

from chezmoi_source_support import ROOT, SourceFixture, expected_entries, snapshot


_spec = importlib.util.spec_from_file_location("codex_legacy_policy", ROOT / "lib/config_sync.py")
_legacy = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_legacy)
POLICY = _legacy.CODEX_POLICY
RETIRED = _legacy.CODEX_RETIRED
PORTABLE = ROOT / "common/codex/.codex/config.toml"
MANIFEST = ROOT / "home/.chezmoidata/codex-policy.json"
HOST = "win" if os.name == "nt" else "common-only"


def at_path(document, path):
    for component in path:
        document = document[component]
    return document


def policy_text(changes=None, missing=None):
    """Synthetic policy with independently addressable required native paths."""
    portable = tomllib.loads(PORTABLE.read_text(encoding="utf-8"))
    changes = {} if changes is None else changes
    lines = []
    for path, _expected in POLICY:
        if path == missing:
            continue
        value = changes.get(path, at_path(portable, path))
        lines.append(".".join(json.dumps(key) for key in path) + " = " + json.dumps(value))
    return "\n".join(lines) + "\n"


class CodexPolicyMetadataTests(unittest.TestCase):
    def test_metadata_has_exact_legacy_paths_and_types_without_values(self):
        self.assertTrue(MANIFEST.is_file(), "native Codex ownership manifest is missing")
        expected = {"codexPolicy": {
            "owned": [{"path": list(path), "type": {str: "string", bool: "bool", list: "string-array"}[kind]}
                      for path, kind in POLICY],
            "retired": [list(path) for path in RETIRED],
        }}
        self.assertEqual(json.loads(MANIFEST.read_text(encoding="utf-8")), expected)
        self.assertEqual(len(expected["codexPolicy"]["owned"]), 18)
        self.assertEqual(len(expected["codexPolicy"]["retired"]), 3)


class CodexNativeTests(unittest.TestCase):
    def prepare(self, fixture, live=None, portable=None):
        target = fixture.destination / ".codex/config.toml"
        self.assertIn(".codex/config.toml", expected_entries(HOST))
        target.parent.mkdir(exist_ok=True)
        if live is not None:
            target.write_bytes(live.encode("utf-8"))
        if portable is not None:
            (fixture.source / "common/codex/.codex/config.toml").write_bytes(portable.encode("utf-8"))
        return target

    def apply(self, fixture, target):
        result = fixture.run("apply", str(target))
        self.assertEqual(result.returncode, 0, result.stderr)
        return tomllib.loads(target.read_bytes().decode("utf-8"))

    def assert_refused(self, fixture, target):
        before = target.read_bytes() if target.exists() else None
        source_before = snapshot(fixture.source)
        result = fixture.run("apply", str(target))
        self.assertNotEqual(result.returncode, 0, "unsafe TOML input was accepted")
        self.assertNotIn("not managed", result.stderr)
        self.assertEqual(target.read_bytes() if target.exists() else None, before)
        self.assertEqual(snapshot(fixture.source), source_before)
        return result

    def test_native_round_trip_retains_unknown_types_and_exact_ownership(self):
        initial = '''# Canonical output intentionally replaces comments.
model = "old"
sandbox_mode = "old"
sandbox_workspace_write = {network_access = true}
"features.js_repl" = "literal survives"
max_integer = 9223372036854775807
min_integer = -9223372036854775808
float = 1.25
"*" = {"literal.dot" = [true, 7, {stamp = 2026-11-01T12:34:56.123456789-08:00}]}
offset = 2026-11-01T12:34:56-08:00
utc = 2026-11-01T20:34:56Z
escaped = "first\\r\\nsecond"
[features]
js_repl = true
unknown = false
[projects."/tmp/synthetic.project"]
trust_level = "trusted"
[unknown."literal.dot"]
"*" = "kept"
[[unknown.providers]]
name = "first"
stamp = 2026-11-01T12:34:56+05:30
[[unknown.providers]]
name = "second"
'''
        with SourceFixture(HOST) as fixture:
            target = self.prepare(fixture, initial)
            source_before = snapshot(fixture.source)
            expected = tomllib.loads(initial)
            portable = tomllib.loads(PORTABLE.read_text(encoding="utf-8"))
            for path in RETIRED:
                parent = expected
                for key in path[:-1]:
                    parent = parent[key]
                del parent[path[-1]]
            for path, _kind in POLICY:
                parent = expected
                for key in path[:-1]:
                    parent = parent.setdefault(key, {})
                parent[path[-1]] = at_path(portable, path)
            self.assertEqual(self.apply(fixture, target), expected)
            normalized = target.read_bytes()
            self.assertNotIn(b"# Canonical", normalized)
            self.assertIn(b"123456789", normalized)
            self.apply(fixture, target)
            self.assertEqual(target.read_bytes(), normalized)
            self.assertEqual(snapshot(fixture.source), source_before)
            diff = fixture.run("diff", str(target))
            self.assertEqual((diff.returncode, diff.stdout), (0, ""), diff.stderr)
            self.assertEqual(list(Path(fixture.env["PATH"]).iterdir()), [])
            self.assertFalse((fixture.source / ".venv-sync").exists())
            if os.name != "nt":
                self.assertEqual(target.stat().st_mode & 0o777, 0o600)

    def test_missing_empty_and_whitespace_initialize_owned_fields(self):
        for live in (None, "", " \n\t"):
            with self.subTest(live=live), SourceFixture(HOST) as fixture:
                target = self.prepare(fixture, live)
                actual = self.apply(fixture, target)
                self.assertEqual(actual, tomllib.loads(PORTABLE.read_text(encoding="utf-8")))

    def test_unknown_portable_fields_never_acquire_ownership(self):
        portable = PORTABLE.read_text(encoding="utf-8") + (
            '\n[unknown]\nnew = "portable"\nstamp = 2026-11-01T12:34:56+05:30\n')
        with SourceFixture(HOST) as fixture:
            target = self.prepare(fixture, '[unknown]\nnew = "live"\n', portable)
            self.assertEqual(self.apply(fixture, target)["unknown"], {"new": "live"})

    def test_local_data_cannot_expand_or_replace_ownership(self):
        with SourceFixture(HOST) as fixture:
            fixture.config.write_text(
                f'[data]\nhost = "{HOST}"\n[data.codexPolicy]\nowned = []\nretired = [["unknown"]]\n',
                encoding="utf-8", newline="\n",
            )
            target = self.prepare(fixture, 'model = "old"\nunknown = "keep"\nsandbox_mode = "old"\n')
            actual = self.apply(fixture, target)
            self.assertEqual(actual["model"], tomllib.loads(PORTABLE.read_text())["model"])
            self.assertEqual(actual["unknown"], "keep")
            self.assertNotIn("sandbox_mode", actual)

    def test_every_required_policy_path_is_present_and_typed(self):
        for path, kind in POLICY:
            invalid = ([False, 1] if kind is list else (False if kind is str else "true"))
            for name, portable in (("missing", policy_text(missing=path)),
                                   ("wrong-type", policy_text({path: invalid}))):
                with self.subTest(path=path, case=name), SourceFixture(HOST) as fixture:
                    target = self.prepare(fixture, 'unknown = "keep"\n', portable)
                    self.assert_refused(fixture, target)

    def test_string_arrays_reject_numbers_and_accept_empty_arrays(self):
        path = ("project_doc_fallback_filenames",)
        for invalid in ('project_doc_fallback_filenames = ["ok", 42]\n',
                        'project_doc_fallback_filenames = ["ok", true]\n'):
            with self.subTest(invalid=invalid), SourceFixture(HOST) as fixture:
                portable = policy_text(missing=path) + invalid
                target = self.prepare(fixture, 'unknown = "keep"\n', portable)
                self.assert_refused(fixture, target)
        with SourceFixture(HOST) as fixture:
            target = self.prepare(fixture, None, policy_text({path: []}))
            self.assertEqual(self.apply(fixture, target)[path[0]], [])

    def test_each_live_ancestor_collision_is_refused_before_assignment(self):
        ancestors = {path[:depth] for path, _kind in POLICY for depth in range(1, len(path))}
        for path in sorted(ancestors):
            for value in ('"local"', "false", "[]", "7"):
                with self.subTest(path=path, value=value), SourceFixture(HOST) as fixture:
                    live = ".".join(json.dumps(key) for key in path) + " = " + value + "\n"
                    target = self.prepare(fixture, live)
                    self.assert_refused(fixture, target)

    def test_each_portable_ancestor_collision_is_refused(self):
        ancestors = {path[:depth] for path, _kind in POLICY for depth in range(1, len(path))}
        for path in sorted(ancestors):
            prefix = ".".join(json.dumps(key) for key in path)
            portable = "\n".join(line for line in policy_text().splitlines()
                                 if not line.startswith(prefix + "."))
            with self.subTest(path=path), SourceFixture(HOST) as fixture:
                target = self.prepare(fixture, 'keep = "live"\n', portable + "\n" + prefix + ' = "collision"\n')
                self.assert_refused(fixture, target)

    def test_malformed_live_and_portable_fail_without_target_replacement(self):
        for malformed in ('[broken\n', 'model = "x"\nmodel = "y"\n', 'key = ', '[]', '\x00'):
            for origin in ("live", "portable"):
                with self.subTest(malformed=malformed, origin=origin), SourceFixture(HOST) as fixture:
                    target = self.prepare(fixture, malformed if origin == "live" else 'keep = "live"\n',
                                          malformed if origin == "portable" else None)
                    self.assert_refused(fixture, target)
        with SourceFixture(HOST) as fixture:
            target = self.prepare(fixture, 'keep = "live"\n', "")
            self.assert_refused(fixture, target)

    def test_recursive_local_temporals_are_refused_in_both_inputs(self):
        cases = ('value = 2026-11-01\n', 'value = 12:34:56\n',
                 'value = 2026-11-01T12:34:56\n',
                 '"literal.dot" = {"*" = [[2026-11-01]]}\n',
                 '[[unknown]]\nvalue = {nested = [12:34:56]}\n',
                 'model = 2026-11-01T12:34:56\n',
                 'sandbox_mode = 2026-11-01\n',
                 '[features]\njs_repl = 12:34:56\n')
        for text in cases:
            for origin in ("live", "portable"):
                with self.subTest(text=text, origin=origin), SourceFixture(HOST) as fixture:
                    fixture.env["TZ"] = "America/Los_Angeles"
                    portable = policy_text() + text if origin == "portable" else None
                    if origin == "portable" and text.startswith("[features]"):
                        portable = policy_text() + "features.js_repl = 12:34:56\n"
                    if origin == "portable" and text.startswith("model ="):
                        portable = policy_text(missing=("model",)) + text
                    target = self.prepare(fixture, text if origin == "live" else 'keep = "live"\n', portable)
                    result = self.assert_refused(fixture, target)
                    self.assertIn("does not support local date/time/datetime", result.stderr)

    def test_local_temporal_refusal_in_utc_and_tokyo(self):
        # Run on Windows too: TZ need not control its native local time zone.
        for timezone in ("UTC", "Asia/Tokyo"):
            for origin in ("live", "portable"):
                with self.subTest(timezone=timezone, origin=origin), SourceFixture(HOST) as fixture:
                    fixture.env["TZ"] = timezone
                    temporal = "unknown = 2026-11-01T12:34:56\n"
                    target = self.prepare(
                        fixture, temporal if origin == "live" else 'keep = "live"\n',
                        policy_text() + temporal if origin == "portable" else None,
                    )
                    result = self.assert_refused(fixture, target)
                    self.assertIn("does not support local date/time/datetime", result.stderr)

    def test_exact_bytes_normalize_physical_crlf_not_explicit_escapes(self):
        live = (b'basic = """\r\nfirst\r\nsecond"""\r\n'
                b"literal = '''\r\nfirst\r\nsecond'''\r\n"
                b'continued = """\r\nfirst\\\r\n \t\r\n  second"""\r\n'
                b'escaped = "first\\r\\nsecond"\r\n')
        portable = policy_text() + ('\n[unknown]\nbasic = """\r\nfirst\r\nsecond"""\r\n'
                                    "literal = '''\r\nfirst\r\nsecond'''\r\n")
        with SourceFixture(HOST) as fixture:
            target = self.prepare(fixture, None, portable)
            target.write_bytes(live)
            actual = self.apply(fixture, target)
            self.assertEqual(actual["basic"].encode(), b"first\nsecond")
            self.assertEqual(actual["literal"].encode(), b"first\nsecond")
            self.assertEqual(actual["continued"].encode(), b"firstsecond")
            self.assertEqual(actual["escaped"].encode(), b"first\r\nsecond")
            self.assertEqual(target.read_bytes().count(b"\r"), 0)

    def test_owned_portable_multiline_crlf_and_escaped_values(self):
        path = ("permissions", "workspace-net", "description")
        prefix = ".".join(json.dumps(key) for key in path) + " = "
        for literal, expected in (('"""\r\nfirst\r\nsecond"""', b"first\nsecond"),
                                  ("'''\r\nfirst\r\nsecond'''", b"first\nsecond"),
                                  ('"""\r\nfirst\\\r\n \t\r\n  second"""', b"firstsecond"),
                                  ('"first\\r\\nsecond"', b"first\r\nsecond")):
            with self.subTest(literal=literal), SourceFixture(HOST) as fixture:
                portable = policy_text(missing=path) + prefix + literal + "\r\n"
                target = self.prepare(fixture, None, portable)
                actual = self.apply(fixture, target)
                self.assertEqual(at_path(actual, path).encode(), expected)


if __name__ == "__main__":
    unittest.main()
