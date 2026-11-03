"""Real native Claude transforms with isolated homes and no child tools."""

from decimal import Decimal
import json
import os
from pathlib import Path
import unittest

from chezmoi_source_support import SourceFixture, expected_entries, snapshot


PORTABLE = "common/claude/.claude/settings.json"
TARGET = ".claude/settings.json"


class ClaudeNativeTests(unittest.TestCase):
    def fixture(self):
        return SourceFixture("win" if os.name == "nt" else "common-only")

    def prepare(self, fixture, live=None, portable=None):
        self.assertIn(TARGET, expected_entries(fixture.host))
        self.assertEqual(list(Path(fixture.env["PATH"]).iterdir()), [])
        target = fixture.destination / TARGET
        target.parent.mkdir(parents=True, exist_ok=True)
        if live is not None:
            target.write_bytes(live)
        if portable is not None:
            (fixture.source / PORTABLE).write_bytes(portable)
        managed = fixture.run("managed", "--include=files", "--nul-path-separator")
        self.assert_success(managed)
        self.assertIn(TARGET, {name.replace("\\", "/") for name in managed.stdout.split("\0")})
        return target

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)

    def apply(self, fixture, target):
        result = fixture.run("apply", str(target))
        self.assert_success(result)
        return target.read_bytes()

    def assert_converges(self, fixture, target, content):
        self.assertEqual(self.apply(fixture, target), content)
        result = fixture.run("diff", str(target))
        self.assert_success(result)
        self.assertEqual(result.stdout, "")

    def assert_rejected(self, fixture, target):
        before = target.read_bytes() if target.exists() else None
        source_before = snapshot(fixture.source)
        result = fixture.run("apply", str(target))
        self.assertNotEqual(result.returncode, 0)
        if before is None:
            self.assertFalse(target.exists())
        else:
            self.assertEqual(target.read_bytes(), before)
        self.assertEqual(snapshot(fixture.source), source_before)

    def test_canonical_policy_preserves_local_state_and_private_convergence(self):
        live = {
            "model": "fixture-local-model",
            "permissions": {"allow": ["obsolete"], "ask": ["obsolete"], "deny": ["obsolete"],
                            "additionalDirectories": ["fixture-local-directory"]},
            "hooks": {"FixtureLocal": [{"hooks": [{"type": "command", "command": "fixture-only"}]}]},
            "fixture_unknown": {"zero": 0, "disabled": False, "nil": None, "empty": []},
        }
        with self.fixture() as fixture:
            target = self.prepare(fixture, json.dumps(live).encode())
            portable = json.loads((fixture.source / PORTABLE).read_bytes())
            expected = portable | {"model": live["model"], "fixture_unknown": live["fixture_unknown"]}
            expected["permissions"] = portable["permissions"] | {
                "additionalDirectories": live["permissions"]["additionalDirectories"]}
            expected["hooks"] = portable.get("hooks", {}) | live["hooks"]
            before = snapshot(fixture.source)
            content = self.apply(fixture, target)
            self.assertEqual(json.loads(content), expected)
            for plugin_id in ("agents-md@builtin", "cc-plugin-agents-md@builtin"):
                self.assertEqual(json.loads(content)["pluginConfigs"][plugin_id]["options"]["instructionFiles"],
                                 "claude-md-and-agents-md")
            self.assertFalse(target.is_symlink())
            if os.name != "nt":
                self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            self.assert_converges(fixture, target, content)
            self.assertEqual(snapshot(fixture.source), before)

    def test_missing_empty_and_whitespace_initialize_canonical_policy(self):
        for initial in (None, b"", b" \r\n\t"):
            with self.subTest(initial=initial), self.fixture() as fixture:
                target = self.prepare(fixture, initial)
                portable = json.loads((fixture.source / PORTABLE).read_bytes())
                self.assertEqual(json.loads(self.apply(fixture, target)), portable)

    def test_recursive_merge_replaces_arrays_and_false_zero_null_without_fallback(self):
        portable = {
            "permissions": {"allow": [], "ask": [], "deny": []},
            "nested": {"keep": {"new": False}, "array": [], "bool": False, "zero": 0, "nil": None},
            "hooks": {"event": []}, "reverse": 0,
        }
        live = {
            "permissions": {"allow": ["old"], "ask": ["old"], "deny": ["old"], "local": True},
            "nested": {"keep": {"local": [False, 0, None]}, "array": [1], "bool": 0,
                       "zero": False, "nil": {"old": True}},
            "hooks": {"event": ["old"], "other": ["keep"]}, "reverse": False,
        }
        expected = {
            "permissions": {"allow": [], "ask": [], "deny": [], "local": True},
            "nested": {"keep": {"local": [False, 0, None], "new": False}, "array": [],
                       "bool": False, "zero": 0, "nil": None},
            "hooks": {"event": [], "other": ["keep"]}, "reverse": 0,
        }
        with self.fixture() as fixture:
            target = self.prepare(fixture, json.dumps(live).encode(), json.dumps(portable).encode())
            actual = json.loads(self.apply(fixture, target))
            self.assertEqual(actual, expected)
            self.assertIs(actual["nested"]["bool"], False)
            self.assertIs(type(actual["nested"]["zero"]), int)
            self.assertIs(type(actual["reverse"]), int)
            self.assertIsNone(actual["nested"]["nil"])

    def test_optional_deny_retains_live_array_and_required_empty_arrays_apply(self):
        portable = b'{"permissions":{"allow":[],"ask":[]}}'
        with self.fixture() as fixture:
            target = self.prepare(fixture, b'{"permissions":{"deny":["local-deny"]}}', portable)
            self.assertEqual(json.loads(self.apply(fixture, target)), {
                "permissions": {"allow": [], "ask": [], "deny": ["local-deny"]}})

    def test_invalid_permission_shapes_and_elements_preserve_target(self):
        policies = [{}, {"permissions": None}, {"permissions": []},
                    {"permissions": {"allow": []}}, {"permissions": {"ask": []}}]
        for name in ("allow", "ask", "deny"):
            for invalid in (None, False, 0, "string", {}, [0], [1.25], [False], [None], [[]], [{}]):
                permissions = {"allow": [], "ask": []}
                permissions[name] = invalid
                policies.append({"permissions": permissions})
        for policy in policies:
            with self.subTest(policy=policy), self.fixture() as fixture:
                target = self.prepare(fixture, b'{"keep":"unchanged"}\n', json.dumps(policy).encode())
                self.assert_rejected(fixture, target)

    def test_portable_model_even_null_is_forbidden(self):
        for model in (None, "portable", False):
            with self.subTest(model=model), self.fixture() as fixture:
                policy = {"permissions": {"allow": [], "ask": []}, "model": model}
                target = self.prepare(fixture, b'{"model":"local"}', json.dumps(policy).encode())
                self.assert_rejected(fixture, target)

    def test_invalid_documents_and_trailing_values_preserve_affected_target(self):
        invalid = (b'{"broken":', b'{} trailing', b'{} {}', b'{}\nnull', b'[]', b'null',
                   b'false', b'0', b'"text"', b'{"x":NaN}', b'{"x":Infinity}', b'{"x":01}', b'\xc2\xa0')
        for side in ("live", "portable"):
            for data in invalid:
                with self.subTest(side=side, data=data), self.fixture() as fixture:
                    target = self.prepare(fixture, data if side == "live" else b'{"keep":true}',
                                          data if side == "portable" else None)
                    self.assert_rejected(fixture, target)
        with self.fixture() as fixture:
            target = self.prepare(fixture, portable=b'')
            self.assert_rejected(fixture, target)

    def test_duplicate_keys_use_native_last_value_in_both_documents(self):
        with self.fixture() as fixture:
            target = self.prepare(
                fixture, b'{"local":1,"local":2,"nested":{"keep":false,"keep":true}}',
                b'{"permissions":{"allow":["old"],"allow":[],"ask":[]},"owned":0,"owned":false}')
            self.assertEqual(json.loads(self.apply(fixture, target)), {
                "local": 2, "nested": {"keep": True}, "permissions": {"allow": [], "ask": []},
                "owned": False})

    def test_number_tokens_survive_nested_live_and_portable_values_exactly(self):
        tokens = ["9007199254740993", "9223372036854775808", "123456789012345678901234567890",
                  "1.234567890123456789012345678901", "1e400", "1e-400", "-0", "-0.0",
                  "1E+004", "-2.345678901234567890e-123"]
        numbers = ",".join(tokens)
        portable = ('{"permissions":{"allow":[],"ask":[]},"owned":{"nested":[' + numbers + ']}}').encode()
        live = ('{"local":{"nested":[' + numbers + ']}}').encode()
        for timezone in ("UTC", "America/Los_Angeles", "Asia/Tokyo"):
            with self.subTest(timezone=timezone), self.fixture() as fixture:
                fixture.env["TZ"] = timezone
                target = self.prepare(fixture, live, portable)
                content = self.apply(fixture, target)
                # The callbacks expose raw tokens, including exponent spelling and signed zero.
                actual = json.loads(content, parse_int=lambda token: token, parse_float=lambda token: token)
                self.assertEqual(actual["local"]["nested"], tokens)
                self.assertEqual(actual["owned"]["nested"], tokens)
                decimal = json.loads(content, parse_int=Decimal, parse_float=Decimal)
                self.assertEqual(decimal["local"]["nested"], [Decimal(token) for token in tokens])
                self.assert_converges(fixture, target, content)

    def test_unsafe_unicode_in_keys_or_strings_rejects_both_documents(self):
        unsafe = [b'{"x":"\\ud800"}', b'{"x":"\\udfff"}', b'{"\\ud800":"key"}',
                  b'{"nested":[{"x":"\\ufffd"}]}', b'{"x":"\xff"}',
                  b'{"\xff":"value"}', '{"x":"\ufffd"}'.encode()]
        for side in ("live", "portable"):
            for data in unsafe:
                with self.subTest(side=side, data=data), self.fixture() as fixture:
                    if side == "portable":
                        data = b'{"permissions":{"allow":[],"ask":[]},"unsafe":' + data + b'}'
                    target = self.prepare(fixture, data if side == "live" else b'{"keep":true}',
                                          data if side == "portable" else None)
                    self.assert_rejected(fixture, target)

    def test_valid_unicode_surrogate_pairs_and_literal_policy_include_are_supported(self):
        policy = {
            "permissions": {"allow": [], "ask": []},
            "literal": '{{ not_a_template }} $defaults "quoted" \\ path',
            "unicode": "\U0001f680 \u03b1", "escaped": r"\ud800",
        }
        with self.fixture() as fixture:
            target = self.prepare(fixture, b'{"pair":"\\ud83d\\ude80","literal":"\\\\ud800"}',
                                  json.dumps(policy, ensure_ascii=True).encode())
            before = snapshot(fixture.source)
            content = self.apply(fixture, target)
            self.assertEqual(json.loads(content), policy | {"pair": "\U0001f680"})
            self.assertEqual(snapshot(fixture.source), before)
            self.assert_converges(fixture, target, content)


if __name__ == "__main__":
    unittest.main()
