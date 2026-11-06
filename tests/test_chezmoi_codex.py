"""Native Codex ownership and TOML safety, using only disposable native homes."""

import json
import os
from pathlib import Path
import tomllib
import unittest

from chezmoi_source_support import ROOT, SourceFixture, expected_entries, snapshot


# Frozen oracle for home/.chezmoidata/codex-policy.json, independent of it:
# changing the owned or retired set is a reviewed edit of both files.
POLICY = (
    (("model",), "string"),
    (("model_reasoning_effort",), "string"),
    (("plan_mode_reasoning_effort",), "string"),
    (("personality",), "string"),
    (("default_permissions",), "string"),
    (("approval_policy",), "string"),
    (("approvals_reviewer",), "string"),
    (("project_doc_fallback_filenames",), "string-array"),
    (("features", "network_proxy"), "bool"),
    (("features", "multi_agent"), "bool"),
    (("features", "memories"), "bool"),
    (("permissions", "workspace-net", "description"), "string"),
    (("permissions", "workspace-net", "extends"), "string"),
    (("permissions", "workspace-net", "network", "enabled"), "bool"),
    (("permissions", "workspace-net", "network", "allow_local_binding"), "bool"),
    (("permissions", "workspace-net", "network", "domains", "*"), "string"),
    (("memories", "generate_memories"), "bool"),
    (("memories", "use_memories"), "bool"),
    (("tui", "status_line"), "string-array"),
)
RETIRED = (
    ("sandbox_mode",),
    ("sandbox_workspace_write",),
    ("features", "js_repl"),
)
TYPE_CHECKS = {
    "string": lambda value: type(value) is str,
    "bool": lambda value: type(value) is bool,
    "string-array": lambda value: type(value) is list and all(type(item) is str for item in value),
}
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


def leaves(table, prefix=()):
    for key, value in table.items():
        if isinstance(value, dict):
            yield from leaves(value, prefix + (key,))
        else:
            yield prefix + (key,), value


class CodexPolicyMetadataTests(unittest.TestCase):
    def test_metadata_matches_the_frozen_paths_and_types_without_values(self):
        self.assertTrue(MANIFEST.is_file(), "native Codex ownership manifest is missing")
        expected = {"codexPolicy": {
            "owned": [{"path": list(path), "type": kind} for path, kind in POLICY],
            "retired": [list(path) for path in RETIRED],
        }}
        self.assertEqual(json.loads(MANIFEST.read_text(encoding="utf-8")), expected)
        self.assertEqual((len(POLICY), len(RETIRED)), (19, 3))

    def test_portable_leaves_are_exactly_the_owned_paths_with_their_types(self):
        # An unowned portable key would never deploy (unknown portable fields
        # do not become policy); a retired one would fight the removal.
        actual = dict(leaves(tomllib.loads(PORTABLE.read_text(encoding="utf-8"))))
        self.assertEqual(set(actual), {path for path, _kind in POLICY})
        for path, kind in POLICY:
            with self.subTest(owned=path):
                self.assertTrue(TYPE_CHECKS[kind](actual[path]), f"{path} is not {kind}")
        for path in RETIRED:
            with self.subTest(retired=path):
                self.assertFalse(any(owned[:len(path)] == path for owned, _kind in POLICY))


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

    def test_status_line_sync_preserves_other_tui_settings(self):
        initial = '''[tui]
status_line = ["codex-version"]
status_line_use_colors = false
theme = "local-theme"
[tui.model_availability_nux]
local_model = 4
'''
        with SourceFixture(HOST) as fixture:
            target = self.prepare(fixture, initial)
            expected = tomllib.loads(initial)["tui"]
            expected["status_line"] = tomllib.loads(PORTABLE.read_text())["tui"]["status_line"]
            self.assertEqual(self.apply(fixture, target)["tui"], expected)
            before = target.read_bytes()
            self.apply(fixture, target)
            self.assertEqual(target.read_bytes(), before)

    def test_app_reformat_with_existing_state_is_nonforce_byte_and_metadata_noop(self):
        unknown = ('[unknown]\ninteger = 1\nfloat = 1.0\nflag = false\n'
                   'offset = 2026-11-01T12:34:56.123456789-08:00\n'
                   'escaped = "first\\r\\nsecond"\n'
                   '"literal.dot" = {"*" = [true, 7, "kept"]}\n'
                   '[[unknown.providers]]\nname = "first"\n')
        for newline, final_newline in (("\n", True), ("\r\n", True), ("\r\n", False)):
            with self.subTest(newline=repr(newline), final=final_newline), SourceFixture(HOST) as fixture:
                target = self.prepare(fixture, unknown)
                expected = self.apply(fixture, target)
                self.assertTrue(fixture.state.is_file())
                original = target.read_bytes()
                app_bytes = ("# App formatting and comments stay local.\n" + policy_text() +
                             "\n" + unknown).replace("\n", newline).encode("utf-8")
                if not final_newline:
                    app_bytes = app_bytes.removesuffix(newline.encode())
                self.assertEqual(tomllib.loads(app_bytes.decode()), expected)
                self.assertNotEqual(app_bytes, original)
                target.write_bytes(app_bytes)
                before = target.stat()
                metadata = lambda st: (st.st_dev, st.st_ino, st.st_mode, st.st_uid, st.st_gid,
                                       st.st_nlink, st.st_size, st.st_mtime_ns, st.st_ctime_ns)
                source_before = snapshot(fixture.source)
                flags = ("--mode=file", "--less-interactive", "--force=false")
                for action in ("apply", "apply", "diff"):
                    result = fixture.run(*flags, action, "--exclude=dirs", str(target))
                    self.assertEqual((result.returncode, result.stdout), (0, ""), result.stderr)
                    self.assertEqual(target.read_bytes(), app_bytes)
                    self.assertEqual(metadata(target.stat()), metadata(before))
                self.assertEqual(snapshot(fixture.source), source_before)

    def test_native_semantic_equality_distinguishes_integer_float_and_nan(self):
        with SourceFixture(HOST) as fixture:
            for left, right, expected in (("value = 1", "value = 1.0", "false"),
                                          ("value = nan", "value = nan", "false"),
                                          ("value = 2026-11-01T12:34:56-08:00",
                                           "value = 2026-11-01T12:34:56-08:00", "true")):
                with self.subTest(left=left, right=right):
                    template = "{{ deepEqual (fromToml " + json.dumps(left) + ") (fromToml " + json.dumps(right) + ") }}"
                    result = fixture.run("execute-template", template)
                    self.assertEqual((result.returncode, result.stdout), (0, expected), result.stderr)

    def test_nan_remains_conservative_instead_of_claiming_byte_preservation(self):
        with SourceFixture(HOST) as fixture:
            target = self.prepare(fixture, "unknown = nan\n")
            self.apply(fixture, target)
            app_bytes = ("# App formatting\nunknown = nan\n" + policy_text()).encode()
            target.write_bytes(app_bytes)
            result = fixture.run("cat", str(target))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotEqual(result.stdout.encode(), app_bytes)
            result = fixture.run("--less-interactive", "--force=false", "apply",
                                 "--exclude=dirs", str(target))
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(target.read_bytes(), app_bytes)

    def test_owned_type_changes_and_retired_keys_are_not_formatting_noops(self):
        cases = (policy_text({("model",): 1}),
                 policy_text({("features", "multi_agent"): 1}),
                 policy_text() + 'sandbox_mode = "old"\n')
        for live in cases:
            with self.subTest(live=live), SourceFixture(HOST) as fixture:
                target = self.prepare(fixture)
                expected = self.apply(fixture, target)
                target.write_bytes(live.encode("utf-8"))
                before = target.read_bytes()
                rendered = fixture.run("cat", str(target))
                self.assertEqual(rendered.returncode, 0, rendered.stderr)
                self.assertEqual(tomllib.loads(rendered.stdout), expected)
                self.assertNotEqual(rendered.stdout.encode(), before)
                result = fixture.run("--less-interactive", "--force=false", "apply",
                                     "--exclude=dirs", str(target))
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(target.read_bytes(), before)

    def test_matching_policy_still_refuses_invalid_live_input(self):
        for suffix in (b'unknown = 2026-11-01\n', b'unknown = "\xff"\n',
                       b'unknown = 1\nunknown = 2\n'):
            with self.subTest(suffix=suffix), SourceFixture(HOST) as fixture:
                target = self.prepare(fixture)
                self.apply(fixture, target)
                target.write_bytes(suffix + policy_text().encode())
                self.assert_refused(fixture, target)

    def test_matching_live_policy_still_validates_complete_portable_input(self):
        for portable in (policy_text(missing=("model",)),
                         policy_text({("model",): False}),
                         policy_text() + 'unknown = 2026-11-01\n'):
            with self.subTest(portable=portable), SourceFixture(HOST) as fixture:
                target = self.prepare(fixture, policy_text(), portable)
                self.assert_refused(fixture, target)

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
            invalid = {"string-array": [False, 1], "string": False, "bool": "true"}[kind]
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
