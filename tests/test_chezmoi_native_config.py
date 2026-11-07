"""Black-box evidence for native mutable JSON/TOML; no legacy merge runtime."""

import json
import os
from pathlib import Path
import shutil
import tomllib
import unittest

from chezmoi_support import ChezmoiFixture


FIXTURES = Path(__file__).parent / "fixtures" / "chezmoi" / "native-config"


class NativeConfigTests(unittest.TestCase):
    def prepare(self, fixture, kind):
        empty_bin = fixture.root / "empty-bin"
        empty_bin.mkdir(exist_ok=True)
        fixture.env["PATH"] = str(empty_bin)
        name = "modify_private_settings.json" if kind == "json" else "modify_private_config.toml"
        shutil.copyfile(FIXTURES / name, fixture.source / name)
        if kind == "json":
            templates = fixture.source / ".chezmoitemplates"
            templates.mkdir()
            shutil.copyfile(FIXTURES / "portable.json", templates / "portable.json")
        return fixture.destination / ("settings.json" if kind == "json" else "config.toml")

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_json_recursive_merge_preserves_live_values_and_authoritative_types(self):
        with ChezmoiFixture() as fixture:
            target = self.prepare(fixture, "json")
            live = {
                "model": "local",
                "permissions": {"allow": ["old"], "additionalDirectories": ["local"]},
                "x": 1,
                "unknown": {"zero": 0, "empty": [], "nil": None, "disabled": False},
            }
            target.write_text(json.dumps(live), encoding="utf-8")
            source_before = (fixture.source / "modify_private_settings.json").read_bytes()
            self.assert_success(fixture.run("apply"))
            merged = json.loads(target.read_text(encoding="utf-8"))
            self.assertEqual(merged["model"], "local")
            self.assertEqual(merged["permissions"], {"allow": [], "ask": [], "additionalDirectories": ["local"]})
            self.assertIs(merged["x"], False)
            self.assertIsNone(merged["y"])
            self.assertEqual(merged["unknown"], live["unknown"])
            normalized = target.read_bytes()
            self.assert_success(fixture.run("apply"))
            self.assertEqual(target.read_bytes(), normalized)
            self.assertEqual((fixture.source / "modify_private_settings.json").read_bytes(), source_before)
            diff = fixture.run("diff")
            self.assert_success(diff)
            self.assertEqual(diff.stdout, "")

    def test_json_missing_empty_and_whitespace_initialize_objects(self):
        for initial in (None, "", " \n\t"):
            with self.subTest(initial=initial), ChezmoiFixture() as fixture:
                target = self.prepare(fixture, "json")
                if initial is not None:
                    target.write_text(initial, encoding="utf-8")
                self.assert_success(fixture.run("apply"))
                self.assertEqual(json.loads(target.read_text(encoding="utf-8")), json.loads((FIXTURES / "portable.json").read_text()))

    def test_invalid_json_preserves_affected_existing_target(self):
        for initial in ('{"broken":', '{} trailing', '[]', 'null', 'false', '1', '"text"'):
            with self.subTest(initial=initial), ChezmoiFixture() as fixture:
                target = self.prepare(fixture, "json")
                target.write_text(initial, encoding="utf-8")
                before = target.read_bytes()
                result = fixture.run("apply")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(target.read_bytes(), before)

    def test_builtin_jq_returns_result_list_and_native_json_limits(self):
        with ChezmoiFixture() as fixture:
            self.prepare(fixture, "json")
            cases = (
                ('{{ dict "a" false | jq ".a" | toJson }}', [False]),
                ('{{ dict | jq "null, false, []" | toJson }}', [None, False, []]),
                ('{{ fromJson "{\\"duplicate\\":1,\\"duplicate\\":2}" | toJson }}', {"duplicate": 2}),
                ('{{ fromJson "{\\"large\\":9007199254740993}" | jq "." | first | toJson }}', {"large": 9007199254740993}),
                ('{{ fromJson "{\\"large\\":1e400}" | jq "." | first | toJson }}', {"large": "1e400"}),
            )
            for template, expected in cases:
                with self.subTest(template=template):
                    result = fixture.run("execute-template", template)
                    self.assert_success(result)
                    self.assertEqual(json.loads(result.stdout), expected)

    def test_toml_preserves_native_types_literal_paths_and_converges(self):
        with ChezmoiFixture() as fixture:
            fixture.env["TZ"] = "UTC"
            target = self.prepare(fixture, "toml")
            initial = (FIXTURES / "live.toml").read_text(encoding="utf-8")
            target.write_text(initial, encoding="utf-8", newline="\n")
            expected = tomllib.loads(initial)
            expected["features"].update({"*": False, "literal.dot": True, "owned": True})
            del expected["retired"]["setting"]
            source = fixture.source / "modify_private_config.toml"
            source_before = source.read_bytes()
            self.assert_success(fixture.run("apply"))
            self.assertEqual(tomllib.loads(target.read_text(encoding="utf-8")), expected)
            self.assertNotEqual(target.read_text(encoding="utf-8"), initial)
            normalized = target.read_bytes()
            self.assert_success(fixture.run("apply"))
            self.assertEqual(target.read_bytes(), normalized)
            self.assertEqual(source.read_bytes(), source_before)
            diff = fixture.run("diff")
            self.assert_success(diff)
            self.assertEqual(diff.stdout, "")

    def test_native_toml_crlf_boundary_and_lf_normalization(self):
        # TOML permits parser-specific multiline newline normalization. Keep this
        # difference visible and prove a native LF choice without changing escapes.
        initial = 'value = """first\r\nsecond"""\r\nescaped = "first\\r\\nsecond"\r\n'
        for normalize in (False, True):
            with self.subTest(normalize=normalize), ChezmoiFixture() as fixture:
                expression = '.chezmoi.stdin'
                if normalize:
                    expression += ' | replace "\\r\\n" "\\n"'
                template = (
                    '{{- /* chezmoi:modify-template */ -}}\n{{ '
                    + expression + ' | fromToml | toToml }}\n'
                )
                (fixture.source / "modify_config.toml").write_text(
                    template, encoding="utf-8", newline="\n",
                )
                target = fixture.destination / "config.toml"
                target.write_bytes(initial.encode("utf-8"))
                self.assert_success(fixture.run("apply"))
                actual = tomllib.loads(target.read_bytes().decode("utf-8"))
                self.assertEqual(actual["value"], "first\nsecond" if normalize else "first\r\nsecond")
                self.assertEqual(actual["escaped"], "first\r\nsecond")
                before = target.read_bytes()
                self.assert_success(fixture.run("apply"))
                self.assertEqual(target.read_bytes(), before)

    def test_toml_rejects_bad_input_and_non_table_ancestor_without_replacement(self):
        for initial in ('features = "local-value"\n', 'features = [1, 2]\n', '[broken\n'):
            with self.subTest(initial=initial), ChezmoiFixture() as fixture:
                target = self.prepare(fixture, "toml")
                target.write_text(initial, encoding="utf-8")
                before = target.read_bytes()
                self.assertNotEqual(fixture.run("apply").returncode, 0)
                self.assertEqual(target.read_bytes(), before)

    @unittest.skipIf(os.name == "nt", "Windows TZ environment handling is separate native evidence")
    def test_native_toml_local_time_timezone_boundary(self):
        # Characterize an upstream limitation, not an accepted value-loss contract.
        initial = (
            "day = 2026-11-01\nclock = 12:34:56\n"
            "local = 2026-11-01T12:34:56\n"
            "offset = 2026-11-01T12:34:56-08:00\n"
        )
        for timezone in ("UTC", "America/Los_Angeles", "Asia/Tokyo"):
            with self.subTest(timezone=timezone), ChezmoiFixture() as fixture:
                fixture.env["TZ"] = timezone
                result = fixture.run("execute-template", "--with-stdin", "{{ .chezmoi.stdin | fromToml | toToml }}", input=initial)
                self.assert_success(result)
                actual = tomllib.loads(result.stdout)
                expected = tomllib.loads(initial)
                if timezone == "UTC":
                    self.assertEqual(actual, expected)
                elif timezone == "America/Los_Angeles":
                    self.assertEqual(actual["day"], expected["day"])
                    self.assertEqual(actual["offset"], expected["offset"])
                    self.assertEqual(actual["clock"], expected["clock"].replace(hour=20))
                    self.assertEqual(actual["local"], expected["local"].replace(hour=20))
                else:
                    self.assertEqual(actual["day"], expected["day"].replace(month=10, day=31))
                    self.assertEqual(actual["offset"], expected["offset"])
                    self.assertEqual(actual["clock"], expected["clock"].replace(hour=3))
                    self.assertEqual(actual["local"], expected["local"].replace(hour=3))

    def test_delete_path_string_supported_list_rejected_and_set_can_replace_ancestor(self):
        with ChezmoiFixture() as fixture:
            self.prepare(fixture, "toml")
            result = fixture.run("execute-template", '{{ dict "a" (dict "b" 1 "keep" 2) | deleteValueAtPath "a.b" | toJson }}')
            self.assert_success(result)
            self.assertEqual(json.loads(result.stdout), {"a": {"keep": 2}})
            result = fixture.run("execute-template", '{{ dict "a" (dict "b" 1) | deleteValueAtPath (list "a" "b") | toJson }}')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("expected string", result.stderr)
            result = fixture.run("execute-template", '{{ dict "a" "discarded" | setValueAtPath (list "a" "b") true | toJson }}')
            self.assert_success(result)
            self.assertEqual(json.loads(result.stdout), {"a": {"b": True}})


if __name__ == "__main__":
    unittest.main()
