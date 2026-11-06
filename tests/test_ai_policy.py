"""Portable AI policy and agent-instruction invariants, read from the sources.

Standard library only: no chezmoi, sync runtime or network. The native modify
templates carry these portable values onto every host (test_chezmoi_claude.py,
test_chezmoi_codex.py); this suite pins the values themselves. Each check is a
pure function, and the mutation cases prove it rejects the drift it names.
"""

import copy
import json
from pathlib import Path
import re
import shutil
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
# B5 retargets these to the materialized native source (D-3 policy files).
CLAUDE_SETTINGS = ROOT / "common/claude/.claude/settings.json"
CLAUDE_GUIDE = ROOT / "common/claude/.claude/CLAUDE.md"
CODEX_GUIDE = ROOT / "common/codex/.codex/AGENTS.md"
CODEX_RULES = ROOT / "common/codex/.codex/rules/portable.rules"
STUB = ROOT / "CLAUDE.md"
REPOSITORY_GUIDE = ROOT / "AGENTS.md"

# The accepted broad-allow set (docs/config-sync.md, permission policy rationale).
EXPECTED_ALLOW = frozenset({
    "WebSearch",
    "mcp__plugin_everything-claude-code_github__search_code",
    "mcp__plugin_everything-claude-code_github__get_file_contents",
    "Bash(git commit *)",
    "Bash(rmdir *)",
    "Bash(mv *)",
    "Bash(git add *)",
    "Bash(git push *)",
    "Bash(git pull *)",
    "Bash(git clone *)",
    "Bash(git reset *)",
    "Bash(git restore *)",
    "Bash(git checkout *)",
    "Bash(curl *)",
    "Bash(wget *)",
    "Bash(ssh *)",
    "Bash(scp *)",
    "Bash(rsync *)",
    "Bash(tee *)",
    "Bash(source *)",
    "Bash(. *)",
    "Bash(pip install *)",
    "Bash(pip3 install *)",
    "Bash(uv pip install *)",
    "Bash(conda install *)",
    "Bash(mamba install *)",
    "Bash(npm install *)",
    "Bash(pnpm install *)",
    "Bash(yarn add *)",
    "Bash(brew install *)",
    "Bash(gh api *)",
    "Bash(gh pr create *)",
    "Bash(gh pr merge *)",
    "Bash(gh issue create *)",
    "Bash(gh release create *)",
})
# AGENTS.md "Preserve Claude permission tiers": ask holds only sudo; deny holds
# sudo pip/pip3, sudo rm and the exact root and home rm patterns, never with a
# trailing wildcard.
EXPECTED_ASK = ["Bash(sudo *)"]
EXPECTED_DENY = [
    "Bash(sudo pip:*)",
    "Bash(sudo pip3:*)",
    "Bash(sudo rm *)",
    "Bash(rm -rf /)",
    "Bash(rm -fr /)",
    "Bash(rm -rf ~)",
    "Bash(rm -fr ~)",
]
# Ordinary rm, git clean and npx stay out of the arrays so auto mode classifies them.
UNSAFE_ALLOW_FRAGMENTS = ("rm ", "git clean", "sudo", "npx")
# Older clients read only the legacy plugin ID; native AGENTS.md loading needs both.
PLUGIN_IDS = ("agents-md@builtin", "cc-plugin-agents-md@builtin")
INSTRUCTION_FILES = {"options": {"instructionFiles": "claude-md-and-agents-md"}}
# Present and empty, so the native merge clears plugin-copied hooks on a live file.
CLEARED_HOOKS = ("SessionStart", "Stop", "SessionEnd")

CLAUDE_ONLY_BULLET = "- Before destructive or difficult-to-reverse actions"
CODEX_ONLY_FIRST = "- Keep routine, scoped cleanup autonomous"
CODEX_ONLY_LAST = "- Before an exceptionally destructive action"
SHERLOCK_HEADING = b"## Stanford Sherlock\n"

# Routine workspace-local execution stays bounded by the active permission
# profile and host-local rules, never by the portable prompt layer.
ROUTINE_COMMANDS = (
    "git add README.md",
    "git commit -m update",
    "source .venv/bin/activate",
    "bash -lc 'echo $HOME'",
    "python -c 'print(1)'",
    "uv run pytest",
    "conda run -n research python analysis.py",
    "git push origin main",
    "curl -LsS https://example.com",
    "ssh lab-ubuntu hostname",
    "npx prettier --check .",
    "pip install package",
    "gh pr create --fill",
)
REVIEWED_COMMANDS = (
    "git reset --hard HEAD~1",
    "git clean -fd",
    "rm -rf build",
    "rm -f -r build",
    "Remove-Item -Recurse build",
    "rd /s build",
    "shred secret.txt",
    "dd if=image.raw of=device.img",
    "mkfs /dev/example",
    "sudo apt-get update",
)


def read_text(path):
    return path.read_bytes().decode("utf-8")


def claude_policy_problems(settings, expected_allow=EXPECTED_ALLOW):
    problems = []
    permissions = settings.get("permissions") or {}
    allow = permissions.get("allow") or []
    if len(allow) != len(set(allow)) or set(allow) != expected_allow:
        problems.append("permissions.allow differs from the reviewed broad-allow set")
    if permissions.get("ask") != EXPECTED_ASK:
        problems.append("permissions.ask must hold only Bash(sudo *)")
    if permissions.get("deny") != EXPECTED_DENY:
        problems.append("permissions.deny must be exactly the reviewed sudo and root/home rm rules")
    problems.extend(f"permissions.allow names {fragment!r} in {rule!r}"
                    for rule in allow for fragment in UNSAFE_ALLOW_FRAGMENTS if fragment in rule)
    if permissions.get("defaultMode") != "auto":
        problems.append("permissions.defaultMode must be auto")
    auto_mode = settings.get("autoMode") or {}
    if auto_mode.get("classifyAllShell") is not True:
        problems.append("autoMode.classifyAllShell must be true")
    for key in ("allow", "soft_deny"):
        if "$defaults" not in (auto_mode.get(key) or []):
            problems.append(f"autoMode.{key} must keep the literal $defaults")
    if settings.get("effortLevel") != "xhigh":
        problems.append("effortLevel must be xhigh")
    hooks = settings.get("hooks") or {}
    problems.extend(f"hooks.{event} must be present and empty"
                    for event in CLEARED_HOOKS if hooks.get(event) != [])
    if settings.get("attribution") != {"commit": "", "pr": ""}:
        problems.append("attribution must stay disabled for commits and pull requests")
    plugin_configs = settings.get("pluginConfigs") or {}
    problems.extend(f"pluginConfigs.{plugin_id} must load CLAUDE.md and AGENTS.md"
                    for plugin_id in PLUGIN_IDS if plugin_configs.get(plugin_id) != INSTRUCTION_FILES)
    if "model" in settings:
        problems.append("portable settings must not declare model")
    return problems


def codex_rules_problems(text):
    problems = []
    if not text.strip():
        problems.append("portable Codex rules are empty")
    if re.search(r'decision\s*=\s*"allow"', text):
        problems.append("portable Codex rules must not grant cross-host allow rules")
    if re.search(r'decision\s*=\s*"forbidden"', text):
        problems.append("portable Codex rules must keep destructive commands reviewable")
    if re.search(r"(/Users/|/home/|/apps/)", text):
        problems.append("portable Codex rules contain a host-specific path")
    problems.extend(f"routine command remains in portable prompt policy: {command}"
                    for command in ROUTINE_COMMANDS if command in text)
    problems.extend(f"required auto-review guardrail is missing: {command}"
                    for command in REVIEWED_COMMANDS if command not in text)
    return problems


def guide_problems(claude_text, codex_text):
    claude_lines = claude_text.split("\n")
    codex_lines = codex_text.split("\n")
    claude_only = [i for i, line in enumerate(claude_lines) if line.startswith(CLAUDE_ONLY_BULLET)]
    first = [i for i, line in enumerate(codex_lines) if line.startswith(CODEX_ONLY_FIRST)]
    last = [i for i, line in enumerate(codex_lines) if line.startswith(CODEX_ONLY_LAST)]
    if len(claude_only) != 1:
        return ["CLAUDE.md must hold exactly one Claude-only destructive-action bullet"]
    if len(first) != 1 or len(last) != 1 or last[0] < first[0]:
        return ["AGENTS.md must hold exactly one Codex-only destructive-action bullet range"]
    shared_claude = claude_lines[:claude_only[0]] + claude_lines[claude_only[0] + 1:]
    shared_codex = codex_lines[:first[0]] + codex_lines[last[0] + 1:]
    if shared_claude != shared_codex:
        return ["global CLAUDE.md and AGENTS.md diverge outside the tool-specific destructive-action bullets"]
    return []


def sherlock_problems(guides):
    problems = []
    sections = []
    for name, content in guides.items():
        if b"SHERLOCK-KIT" in content:
            problems.append(f"{name}: legacy Sherlock block marker")
        if content.count(SHERLOCK_HEADING) != 1:
            problems.append(f"{name}: expected one Stanford Sherlock section")
            continue
        section = content.split(SHERLOCK_HEADING, 1)[1].split(b"\n## ", 1)[0]
        if not section.strip():
            problems.append(f"{name}: empty Stanford Sherlock section")
        if re.search(rb"\bv?\d+\.\d+(?:\.\d+)?\b", section):
            problems.append(f"{name}: global Sherlock policy must not pin a release")
        sections.append(section)
    if len(sections) == len(guides) and len(set(sections)) != 1:
        problems.append("global Stanford Sherlock sections differ")
    return problems


def stub_problems(stub_text, repository_guide_exists):
    problems = []
    if stub_text.split("\n", 1)[0] != "@AGENTS.md":
        problems.append("CLAUDE.md must start with @AGENTS.md so Claude Code imports the shared guide")
    if not repository_guide_exists:
        problems.append("the AGENTS.md that CLAUDE.md imports is missing")
    return problems


class PortablePolicyTests(unittest.TestCase):
    def test_claude_settings_hold_the_reviewed_policy(self):
        self.assertEqual(claude_policy_problems(json.loads(read_text(CLAUDE_SETTINGS))), [])

    def test_codex_rules_are_prompt_only_portable_guardrails(self):
        self.assertEqual(codex_rules_problems(read_text(CODEX_RULES)), [])

    def test_global_guides_differ_only_in_the_destructive_action_bullets(self):
        self.assertEqual(guide_problems(read_text(CLAUDE_GUIDE), read_text(CODEX_GUIDE)), [])

    def test_global_sherlock_section_is_identical_and_version_free(self):
        guides = {"CLAUDE.md": CLAUDE_GUIDE.read_bytes(), "AGENTS.md": CODEX_GUIDE.read_bytes()}
        self.assertEqual(sherlock_problems(guides), [])

    def test_repository_claude_md_only_imports_agents_md(self):
        self.assertEqual(stub_problems(read_text(STUB), REPOSITORY_GUIDE.is_file()), [])


class PolicyMutationTests(unittest.TestCase):
    """Each check rejects the drift it names; this is the suite's RED evidence."""

    def assert_rejected(self, problems):
        self.assertNotEqual(problems, [], "a policy mutation passed its check")

    def test_claude_mutations(self):
        settings = json.loads(read_text(CLAUDE_SETTINGS))
        mutations = {
            "allow gains a rule": lambda s: s["permissions"]["allow"].append("Bash(make *)"),
            "allow repeats a rule": lambda s: s["permissions"]["allow"].append("WebSearch"),
            "ask gains a rule": lambda s: s["permissions"]["ask"].append("Bash(git clean *)"),
            "deny rm gains a wildcard": lambda s: s["permissions"]["deny"].__setitem__(3, "Bash(rm -rf /*)"),
            "deny drops sudo rm": lambda s: s["permissions"]["deny"].remove("Bash(sudo rm *)"),
            "deny missing": lambda s: s["permissions"].pop("deny"),
            "defaultMode": lambda s: s["permissions"].__setitem__("defaultMode", "acceptEdits"),
            "classifyAllShell": lambda s: s["autoMode"].__setitem__("classifyAllShell", False),
            "allow $defaults": lambda s: s["autoMode"]["allow"].remove("$defaults"),
            "soft_deny $defaults": lambda s: s["autoMode"]["soft_deny"].remove("$defaults"),
            "effortLevel": lambda s: s.__setitem__("effortLevel", "medium"),
            "cleared hook missing": lambda s: s["hooks"].pop("SessionStart"),
            "cleared hook filled": lambda s: s["hooks"]["Stop"].append({"hooks": []}),
            "attribution": lambda s: s["attribution"].__setitem__("commit", "Generated with an agent"),
            "legacy plugin ID": lambda s: s["pluginConfigs"].pop("agents-md@builtin"),
            "new plugin ID": lambda s: s["pluginConfigs"]["cc-plugin-agents-md@builtin"]["options"]
                .__setitem__("instructionFiles", "claude-md"),
            "portable model": lambda s: s.__setitem__("model", None),
        }
        for name, mutate in mutations.items():
            with self.subTest(mutation=name):
                mutated = copy.deepcopy(settings)
                mutate(mutated)
                self.assert_rejected(claude_policy_problems(mutated))
        for rule in ("Bash(rm -r *)", "Bash(git clean *)", "Bash(sudo ls)", "Bash(npx *)"):
            with self.subTest(unsafe=rule):
                mutated = copy.deepcopy(settings)
                mutated["permissions"]["allow"].append(rule)
                # Even a reviewed allow set that names it is refused.
                self.assert_rejected(claude_policy_problems(
                    mutated, expected_allow=frozenset(mutated["permissions"]["allow"])))

    def test_codex_rules_mutations(self):
        rules = read_text(CODEX_RULES)
        mutations = {
            "allow decision": rules + '\nprefix_rule(pattern=["host-only"], decision="allow")\n',
            "forbidden decision": rules + '\nprefix_rule(pattern = ["mkfs"], decision = "forbidden")\n',
            "host path": rules + "\n# /home/someone/bin/tool\n",
            "routine command": rules + "\n# git push origin main\n",
            "guardrail removed": rules.replace("git clean -fd", "git clean"),
            "empty": "",
        }
        for name, text in mutations.items():
            with self.subTest(mutation=name):
                self.assert_rejected(codex_rules_problems(text))

    def test_guide_mutations(self):
        claude, codex = read_text(CLAUDE_GUIDE), read_text(CODEX_GUIDE)
        shared = "- Lead with the result, recommendation, or diagnosis."
        self.assertIn(shared, claude)
        mutations = {
            "shared line diverges": (claude, codex.replace(shared, "- Lead with the diagnosis.")),
            "Claude bullet removed": ("\n".join(line for line in claude.split("\n")
                                                if not line.startswith(CLAUDE_ONLY_BULLET)), codex),
            "Codex range unterminated": (claude, "\n".join(line for line in codex.split("\n")
                                                           if not line.startswith(CODEX_ONLY_LAST))),
            "Codex bullet duplicated": (claude, codex + "\n" + CODEX_ONLY_FIRST + "\n"),
        }
        for name, (claude_text, codex_text) in mutations.items():
            with self.subTest(mutation=name):
                self.assert_rejected(guide_problems(claude_text, codex_text))

    def test_sherlock_mutations(self):
        claude, codex = CLAUDE_GUIDE.read_bytes(), CODEX_GUIDE.read_bytes()
        pinned = SHERLOCK_HEADING + b"- Use sherlock-kit v0.7.0.\n"
        mutations = {
            # Both copies, so only the version check can reject it.
            "release pinned": (claude.replace(SHERLOCK_HEADING, pinned), codex.replace(SHERLOCK_HEADING, pinned)),
            "sections differ": (claude, codex.replace(SHERLOCK_HEADING, SHERLOCK_HEADING + b"- Codex only.\n")),
            "heading repeated": (claude, codex + b"\n" + SHERLOCK_HEADING + b"- again\n"),
            "section empty": (claude.replace(SHERLOCK_HEADING, SHERLOCK_HEADING + b"\n## Next\n"), codex),
            "legacy marker": (claude, codex + b"\n<!-- SHERLOCK-KIT -->\n"),
        }
        for name, (claude_bytes, codex_bytes) in mutations.items():
            with self.subTest(mutation=name):
                self.assert_rejected(sherlock_problems({"CLAUDE.md": claude_bytes, "AGENTS.md": codex_bytes}))

    def test_stub_mutations(self):
        stub = read_text(STUB)
        self.assert_rejected(stub_problems("# Claude Code\n" + stub, True))
        self.assert_rejected(stub_problems(stub.replace("@AGENTS.md", "@AGENTS.md\r", 1), True))
        self.assert_rejected(stub_problems(stub, False))


CODEX = shutil.which("codex")


@unittest.skipUnless(CODEX, "optional installed-Codex exec-policy checks (codex not on PATH)")
class InstalledCodexExecPolicyTests(unittest.TestCase):
    def check(self, *command):
        result = subprocess.run([CODEX, "execpolicy", "check", "--rules", str(CODEX_RULES), "--", *command],
                                capture_output=True, text=True, encoding="utf-8", timeout=60,
                                stdin=subprocess.DEVNULL, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_simple_file_operations_match_no_rule(self):
        for command in (("rm", "artifact.txt"), ("rm", "-f", "artifact.txt"),
                        ("rmdir", "empty-directory"), ("mv", "source.txt", "destination.txt"),
                        ("git", "reset", "--soft", "HEAD~1")):
            with self.subTest(command=command):
                output = self.check(*command)
                self.assertRegex(output, r'"matchedRules"\s*:\s*\[\]')
                self.assertNotRegex(output, r'"decision"\s*:')

    def test_destructive_commands_prompt_for_review(self):
        for command in REVIEWED_COMMANDS:
            with self.subTest(command=command):
                self.assertRegex(self.check(*command.split()), r'"decision"\s*:\s*"prompt"')


if __name__ == "__main__":
    unittest.main()
