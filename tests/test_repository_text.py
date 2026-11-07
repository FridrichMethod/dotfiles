"""Tracked text names no retired mechanism and every Markdown link resolves.

The chezmoi migration retired the Stow deployment, the configuration parser
chain, the old updaters, the payload transition and the package trees the
native source replaced (common/ and the host directories). Their names may
stay only in the historical record under docs/chezmoi-migration/ and on the
lines of the reviewed allowlist KEPT below. Each entry names its kind:

- RESIDUE: an ignore line that keeps a host's leftover from stalling updates,
  the test that pins it, or the doc line naming that leftover;
- RECOVERY: the one pointer from an old-layout home to its recovery release;
- NEGATIVE: a native test line (or the doc line naming such a pinned check)
  that fails if a retired name, file, flag, row or step comes back.

Each entry covers an exact number of hit lines, so a stale entry, a copied
kept line or a hit matching two entries fails too. Paths are scanned as well.
The link check covers every tracked Markdown file, history included: relative
targets must be tracked files or directories, and #anchors GitHub heading slugs.
"""
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SELF = "tests/test_repository_text.py"
HISTORY = "docs/chezmoi-migration/"

RETIRED = re.compile("|".join((
    r"stow",
    r"tomlkit", r"config_sync", r"(?<![\w-])config-sync\.sh", r"(?:structured|ai)-config-sync",
    r"\bai-sync\b", r"sync[-_ ]?(?:runtime|python)", r"venv[-_ ]?(?:sync|python)",
    r"setup-sync", r"requirements-sync",
    r"(?:claude-settings|codex-config|codex-rules|fcitx5-profile|codex-instructions)-sync",
    r"codex-portable", r"migrate-portable", r"legacy_?write_?allowed",
    r"(?-i:DOTFILES_DIR)\b", r"(?-i:DOTFILES_HOST)\b", r"(?-i:_?DOTFILES_PAYLOAD_(?:AUTO_UPDATE|CHECKED))",
    r"dotfiles-update", r"awesome-skills-update", r"dotfiles-sync-(?:unix|windows)", r"windows-link-trust",
    r"(?<![\w-])(?:unix|windows)-installer", r"installer-contract", r"(?<![\w-])update-hooks(?![\w-])",
    r"sherlock-kit\.md", r"\bstage[ -]?6\b",
    # A package path from before the native source moved into home/, in
    # either separator; home/.hosts/<role>/ paths are native.
    r"(?:(?<=dotfiles/)|(?<![\w./\\~$-]))(?:common|mac|sherlock|wsl-ubuntu|lab-ubuntu|marlowe|win)/(?-i:[a-z._])",
    r"(?:(?<=dotfiles\\)|(?<![\w./\\~$-]))(?:common|win)\\(?-i:[a-z._])",
)), re.IGNORECASE)

RESIDUE, RECOVERY, NEGATIVE = "residue", "recovery", "negative"


@dataclass(frozen=True)
class Kept:
    path: str
    fragment: str
    count: int
    kind: str
    why: str


@dataclass(frozen=True)
class Hit:
    path: str
    line: int  # 0: the path itself
    text: str


HOST = "the host is [data].host alone: an environment DOTFILES_HOST is ignored or cleared"
FLAG = "the retired deployment flag is refused or absent"
STEPS = "native output, plans and HUMAN blocks name no retired deployment step or tool"
VENV = "the retired parser environment never appears"
HOOK = "a retired updater planted as a tripwire never runs"
PATH_AUDIT = "the e2e audit fails a retired deployment tool on the login PATH or a link into the clone"
VENV_AUDIT = "the e2e audit fails when the clone holds the retired parser environment"
POLICY = "the e2e HUMAN-block policy fails the retired deployment steps"
SUBMODULES = "names the retired submodule checkouts a host may still hold, which .gitignore hides"
KEPT = (
    Kept(".gitignore", "/.venv-sync/", 1, RESIDUE, "hides a host's leftover parser environment until it is removed"),
    Kept("tests/test_chezmoi_source_state.py", '"/.venv-sync/"', 1, RESIDUE, "pins that .gitignore line"),
    Kept("README.md", "Homes still deployed by GNU Stow", 1, RECOVERY, "points an old home at bf99958"),
    Kept("docs/bootstrap.md", "`common/", 3, RESIDUE, SUBMODULES),
    Kept("docs/payloads.md", "| `common/", 4, RESIDUE, SUBMODULES),
    Kept("docs/testing.md", "`audit-no-stow`", 1, NEGATIVE, "names the pinned e2e audit step: " + PATH_AUDIT),
    Kept("tests/bootstrap-manifest.sh", "DOTFILES_HOST", 5, NEGATIVE, HOST),
    Kept("tests/bootstrap.ps1", "'DOTFILES_HOST'", 1, NEGATIVE, HOST),
    Kept("tests/bootstrap.ps1", "stow-all", 1, NEGATIVE, STEPS),
    Kept("tests/bootstrap.ps1", "not stowed", 1, NEGATIVE, STEPS),
    Kept("tests/bootstrap.ps1", "name Stow", 2, NEGATIVE, STEPS),
    Kept("tests/bootstrap.ps1", "-match 'stow'", 1, NEGATIVE, STEPS),
    Kept("tests/doctor.sh", "--legacy-stow", 2, NEGATIVE, FLAG),
    Kept("tests/doctor.sh", "DOTFILES_HOST", 11, NEGATIVE, HOST),
    Kept("tests/doctor.sh", "absent='venv-sync stow-links'", 1, NEGATIVE, "the doctor lists no retired rows"),
    Kept("tests/doctor.sh", "'stow-all'", 1, NEGATIVE, STEPS),
    Kept("tests/doctor.sh", "../../dotfiles/common/coding-agent-kit/", 1, NEGATIVE,
         "a link the retired kit package left on a host changes no payload row"),
    Kept("tests/powershell-profile.ps1", "'dotfiles-update'", 1, NEGATIVE, HOOK),
    Kept("tests/setup-host.sh", "stow_mentions", 12, NEGATIVE, STEPS),
    Kept("tests/setup-host.sh", "--legacy-stow", 4, NEGATIVE, FLAG),
    Kept("tests/setup-host.sh", "DOTFILES_HOST", 2, NEGATIVE, HOST),
    Kept("tests/setup-host.sh", "# stow, apt-get", 1, NEGATIVE, "the retired tool is a tripwire"),
    Kept("tests/setup-host.sh", "# Stow. The fixture", 1, NEGATIVE, STEPS),
    Kept("tests/setup-host.sh", 'spell "stow"', 1, NEGATIVE, STEPS),
    Kept("tests/setup-host.sh", "~ /stow/", 1, NEGATIVE, STEPS),
    Kept("tests/setup-host.sh", "chsh stow apt-get", 1, NEGATIVE, "the retired tool is a tripwire"),
    Kept("tests/setup-host.sh", "names no Stow", 2, NEGATIVE, STEPS),
    Kept("tests/setup-host.sh", "'stowed'", 1, NEGATIVE, STEPS),
    Kept("tests/shell-profile.sh", "dotfiles-update", 1, NEGATIVE, HOOK),
    Kept("tests/test-entrypoints.sh", "grep -Fqi stow", 2, NEGATIVE, "tests/run.sh requires no retired tool"),
    Kept("tests/test-entrypoints.sh", "mentions GNU Stow", 2, NEGATIVE, "tests/run.sh requires no retired tool"),
    Kept("tests/test-entrypoints.sh", "\\bstow\\b", 1, NEGATIVE, "no ci.yml job installs the retired tool"),
    Kept("tests/test_ai_policy.py", "AUTO_MODE_RETIRED = ", 1, NEGATIVE, "auto-mode prose names no retired path"),
    Kept("tests/test_ai_policy.py", "soft_deny names", 2, NEGATIVE, "mutations of that auto-mode prose check"),
    Kept("tests/test_chezmoi_codex.py", '".venv-sync").exists()', 1, NEGATIVE, VENV),
    Kept("tests/test_chezmoi_guard.py", '"dotfiles-update"', 1, NEGATIVE, HOOK),
    Kept("tests/test_chezmoi_integration.py", '".venv-sync"', 1, NEGATIVE, VENV),
    Kept("tests/test_chezmoi_integration.py", '"--migrate-portable"', 1, NEGATIVE, "the retired migration flag is refused"),
    Kept("tests/test_chezmoi_native_config.py", '".venv-sync").exists()', 1, NEGATIVE, VENV),
    Kept("tests/test_chezmoi_provision.py", "DOTFILES_HOST", 6, NEGATIVE, HOST),
    Kept("tests/test_chezmoi_provision.py", "--legacy-stow", 2, NEGATIVE, FLAG),
    Kept("tests/test_chezmoi_provision.py", "test_legacy_stow_flag", 1, NEGATIVE, FLAG),
    Kept("tests/test_chezmoi_provision.py", "excludes_sync_and_stow_steps", 1, NEGATIVE, STEPS),
    Kept("tests/test_chezmoi_provision.py", "self.assertNotIn(", 5, NEGATIVE, STEPS),
    Kept("tests/test_chezmoi_provision.py", "require_stow_or_sync_runtime", 1, NEGATIVE, STEPS),
    Kept("tests/test_chezmoi_provision.py", '{"stow", "stow-links", "venv-sync"}', 1, NEGATIVE, STEPS),
    Kept("tests/test_chezmoi_provision.py", '".venv-sync").exists()', 1, NEGATIVE, VENV),
    Kept("tests/test_chezmoi_source_state.py", '["DOTFILES_HOST"]', 1, NEGATIVE, HOST),
    Kept("tests/test_chezmoi_source_state.py", '".venv-sync").exists()', 1, NEGATIVE, VENV),
    Kept("tests/test_chezmoi_takeover_windows.py", '"dotfiles-update"', 1, NEGATIVE, HOOK),
    Kept("tests/test_environment.py", '"DOTFILES_SYNC_PYTHON"', 1, NEGATIVE, "the retired interpreter knob is cleared"),
    Kept("tests/e2e-harness.ps1", "HW-stow judgment fail", 1, NEGATIVE, POLICY),
    Kept("tests/e2e-harness.ps1", "AI-sync", 1, NEGATIVE, VENV_AUDIT),
    Kept("tests/e2e-harness.sh", "stow", 31, NEGATIVE, PATH_AUDIT + "; " + POLICY),
    Kept("tests/e2e-harness.sh", "retired Stow step", 1, NEGATIVE, POLICY),
    Kept("tests/e2e-harness.sh", "E2E_STOW_START=$1", 1, NEGATIVE, PATH_AUDIT),
    Kept("tests/e2e-harness.sh", ".venv-sync", 4, NEGATIVE, VENV_AUDIT),
    Kept("tests/e2e-harness.sh", "sync-runtime", 4, NEGATIVE, VENV_AUDIT),
    Kept("tests/e2e-harness.sh", "doctor.sh, a sync runtime", 1, NEGATIVE, VENV_AUDIT),
    Kept("tests/e2e-harness.sh", "(a sync runtime in the clone", 1, NEGATIVE, VENV_AUDIT),
    Kept("tests/e2e-harness.sh", "'sync runtime guard", 2, NEGATIVE, VENV_AUDIT),
    Kept("tests/e2e-harness.sh", "AI-sync runtime directory (or", 1, NEGATIVE, VENV_AUDIT),
    Kept("tests/e2e-harness.sh", "hides the AI-sync runtime", 1, NEGATIVE, VENV_AUDIT),
    Kept("tests/e2e/inside.sh", "e2e_stow_start", 1, NEGATIVE, PATH_AUDIT),
    Kept("tests/e2e/lib/assert.sh", "stow", 17, NEGATIVE, PATH_AUDIT),
    Kept("tests/e2e/lib/assert.sh", "(a Stow link", 1, NEGATIVE, PATH_AUDIT),
    Kept("tests/e2e/lib/assert.sh", "E2E_STOW_START)", 2, NEGATIVE, PATH_AUDIT),
    Kept("tests/e2e/lib/assert.sh", "E2E_STOW_START=''", 1, NEGATIVE, PATH_AUDIT),
    Kept("tests/e2e/lib/assert.sh", "$E2E_STOW_START$E2E_NL", 1, NEGATIVE, PATH_AUDIT),
    Kept("tests/e2e/lib/assert.sh", "AI-sync", 2, NEGATIVE, VENV_AUDIT),
    Kept("tests/e2e/lib/assert.sh", "E2E_SYNC_VENV=.venv-sync", 1, NEGATIVE, VENV_AUDIT),
    Kept("tests/e2e/lib/common.ps1", "AI-sync", 2, NEGATIVE, VENV_AUDIT),
    Kept("tests/e2e/lib/common.ps1", "'.venv-sync'", 1, NEGATIVE, VENV_AUDIT),
    Kept("tests/e2e/lib/flow-win.ps1", "sync-runtime audits", 1, NEGATIVE, VENV_AUDIT),
    Kept("tests/e2e/lib/steps.ps1", "sync-runtime audits", 1, NEGATIVE, VENV_AUDIT),
    Kept("tests/e2e/lib/steps.ps1", "restow task", 1, NEGATIVE, "the e2e audit fails any dotfiles scheduled task"),
    Kept("tests/e2e/lib/steps.ps1", "AI-sync", 1, NEGATIVE, VENV_AUDIT),
    Kept("tests/e2e/lib/steps.sh", "stow", 6, NEGATIVE, PATH_AUDIT),
    Kept("tests/e2e/lib/steps.sh", '-n "$E2E_STOW_START"', 1, NEGATIVE, PATH_AUDIT),
    Kept("tests/e2e/lib/steps.sh", "Stow is no longer wrapped", 1, NEGATIVE, PATH_AUDIT),
    Kept("tests/e2e/lib/steps.sh", "AI-sync", 1, NEGATIVE, VENV_AUDIT),
    Kept("tests/e2e/run.ps1", "AI-sync", 1, NEGATIVE, VENV_AUDIT),
)


def tracked(root, *paths):
    out = subprocess.run(["git", "ls-files", "-z", "--", *paths], cwd=root,
                         capture_output=True, check=True).stdout
    return sorted(p for p in out.decode("utf-8").split("\0") if p)


def retired_hits(root, files):
    hits = []
    for rel in files:
        if rel == SELF or rel.startswith(HISTORY):
            continue
        if RETIRED.search(rel):
            hits.append(Hit(rel, 0, rel))
        path = root / rel
        if path.is_symlink() or not path.is_file():
            continue
        data = path.read_bytes()
        if b"\0" in data[:8000]:
            continue
        for number, line in enumerate(data.decode("utf-8", "replace").splitlines(), 1):
            if RETIRED.search(line):
                hits.append(Hit(rel, number, line.strip()))
    return hits


def review(hits, kept):
    problems, covered = [], {entry: 0 for entry in kept}
    for hit in hits:
        owners = [e for e in kept if hit.line and e.path == hit.path and e.fragment in hit.text]
        if not owners:
            problems.append(f"{hit.path}:{hit.line}: unreviewed retired name: {hit.text[:160]}")
        elif len(owners) > 1:
            problems.append(f"{hit.path}:{hit.line}: matches {len(owners)} allowlist entries")
        else:
            covered[owners[0]] += 1
    for entry, count in covered.items():
        if count != entry.count:
            problems.append(f"{entry.path}: allowlist entry {entry.fragment!r} covers {count} lines, not {entry.count}")
    return problems


FENCE = re.compile(r"^ {0,3}(?:```|~~~)")
HEADING = re.compile(r"^ {0,3}#{1,6}\s+(.*?)\s*#*\s*$")
LINK = re.compile(r"(?<!\\)\[[^\]]*\]\(([^()\s]+)(?:\s+\"[^\"]*\")?\)")
SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


def prose(text):
    lines, fenced = [], False
    for line in text.split("\n"):
        if FENCE.match(line):
            fenced = not fenced
            lines.append("")
        else:
            lines.append("" if fenced else line)
    return "\n".join(lines)


def heading_slugs(text):
    slugs, seen = set(), {}
    for line in prose(text).split("\n"):
        match = HEADING.match(line)
        if match:
            slug = re.sub(r"[^\w\- ]", "", match.group(1).strip().lower()).replace(" ", "-")
            count = seen.get(slug, 0)
            seen[slug] = count + 1
            slugs.add(slug if count == 0 else f"{slug}-{count}")
    return slugs


def relative_links(text):
    body = prose(text)
    for match in LINK.finditer(body):
        if not SCHEME.match(match.group(1)):
            yield body.count("\n", 0, match.start()) + 1, match.group(1)


def resolve(source, target):
    parts = []
    for part in (PurePosixPath(source).parent / target).parts:
        if part == "..":
            if not parts:
                return None
            parts.pop()
        elif part != ".":
            parts.append(part)
    return "/".join(parts)


def broken_links(root, files):
    files = set(files)
    dirs = {str(p) for f in files for p in PurePosixPath(f).parents}
    slugs, problems = {}, []
    for source in sorted(f for f in files if f.endswith(".md")):
        if not (root / source).is_file():
            problems.append(f"{source}: tracked but missing from the work tree")
            continue
        for number, target in relative_links((root / source).read_text(encoding="utf-8")):
            path, _, anchor = target.partition("#")
            dest = resolve(source, path) if path else source
            if dest is None or (dest.rstrip("/") not in files and dest.rstrip("/") not in dirs):
                problems.append(f"{source}:{number}: no tracked target {target}")
                continue
            if anchor and dest.endswith(".md"):
                if dest not in slugs:
                    target_file = root / dest
                    slugs[dest] = heading_slugs(target_file.read_text(encoding="utf-8")) if target_file.is_file() else set()
                if anchor not in slugs[dest]:
                    problems.append(f"{source}:{number}: no heading for {target}")
    return problems


RETIRED_SAMPLES = (
    "GNU Stow", "./stow-all.sh mac", "stow-all.ps1", ".stowrc", ".stow-local-ignore", "stow-links",
    "H7-stow", "HW-stow", "HW-auto-stow-task", "Dotfiles-Restow-0123456789abcdef", "--legacy-stow",
    "-LegacyStow", "BOOTSTRAP_LEGACY_STOW", "DOTFILES_AUTO_STOW=0", "Test-SetupStowed", "the stowed .zshrc",
    "tomlkit==0.13", "lib/config_sync.py", "tests/config-sync.sh", "structured-config-sync",
    "tests/ai-config-sync.sh", "AI-sync runtime", "lib/sync-runtime.sh", "Test-BootstrapSyncRuntime",
    "DOTFILES_SYNC_PYTHON", "$syncPython", "Get-BootstrapVenvPython", ".venv-sync", "./setup-sync.sh", "the sync runtime",
    "S4-setup-sync", "W1-setup-sync", "requirements-sync.txt", "claude-settings-sync", "codex-config-sync",
    "codex-rules-sync", "fcitx5-profile-sync", "codex-instructions-sync", "filter.codex-portable",
    "--migrate-portable", "dotfiles_legacy_write_allowed", "Test-DotfilesLegacyWriteAllowed",
    "${DOTFILES_DIR:-$HOME/dotfiles}", "DOTFILES_HOST=win", "DOTFILES_PAYLOAD_AUTO_UPDATE=0",
    "_DOTFILES_PAYLOAD_CHECKED", "scripts/dotfiles-update.sh", "scripts/awesome-skills-update.sh",
    ".git/dotfiles-sync-unix", "dotfiles-sync-windows", "lib/windows-link-trust.ps1",
    "tests/unix-installer.sh", "unix-installer-integration", "docs/windows-installer.md",
    "docs/installer-contract.md", "tests/update-hooks.ps1", "- id: update-hooks", "docs/sherlock-kit.md",
    "until Stage 6", "stage-6-retirement.md", "common/claude/.claude/settings.json",
    "~/dotfiles/common/zsh/.zshrc", "win/powershell/Documents/PowerShell/profile.ps1", "deploys win\\wsl",
    "mac/git/.gitconfig_local", "dotfiles\\win\\terminal",
)
NATIVE_SAMPLES = (
    "scripts/chezmoi-update.sh", "scripts/payload-update.sh --now", "sync-payloads", "sync-skills",
    "_DOTFILES_CHECKED", "DOTFILES_AUTO_UPDATE=0", "DOTFILES_COLOR", "DOTFILES_TEST_CHEZMOI",
    "Resolve-DotfilesDirectory", "$DotfilesDir", "dotfiles_dir=$HOME/dotfiles", "README.md#auto-update-hooks",
    "H7-native", "HW-native", "W1-chezmoi", "docs/config-sync.md", "home/.policy/codex-config.toml",
    "home/.chezmoidata/codex-policy.json", "https://github.com/FridrichMethod/sherlock-kit", ".venv/",
    "uv sync", "Stage 5", "~/.codex/AGENTS.override.md", "tests/test_chezmoi_takeover_unix.py",
    "persistentState", "native-config", "an unmarked home runs no updater", "audit-sync-venv",
    "home/.hosts/win/.ssh/config.d/legacy.conf", "docs/update-contract.md", "tests/repository-text.sh",
    "home/.hosts/wsl-ubuntu/.config/sh/.profile", "--host wsl-ubuntu\\n", "mac/Ubuntu", "common-only",
    "$HOME\\.ssh\\id_ed25519",
)


class RetiredNameTests(unittest.TestCase):
    def test_pattern_matches_every_retired_spelling(self):
        self.assertEqual([s for s in RETIRED_SAMPLES if not RETIRED.search(s)], [])

    def test_pattern_spares_native_names(self):
        self.assertEqual([s for s in NATIVE_SAMPLES if RETIRED.search(s)], [])

    def test_review_reports_unreviewed_ambiguous_and_miscounted(self):
        one = Kept("a", "x stow", 1, NEGATIVE, "why")
        hits = [Hit("a", 1, "x stow y"), Hit("a", 2, "x stow z"), Hit("b", 1, "stow"), Hit("p/stow", 0, "p/stow")]
        problems = review(hits, (one, Kept("a", "stow z", 1, NEGATIVE, "why"), Kept("c", "gone", 1, RESIDUE, "why")))
        self.assertTrue(any("a:2: matches 2" in p for p in problems), problems)
        self.assertTrue(any(p.startswith("b:1: unreviewed") for p in problems), problems)
        self.assertTrue(any(p.startswith("p/stow:0: unreviewed") for p in problems), problems)
        self.assertTrue(any("'gone' covers 0 lines" in p for p in problems), problems)
        self.assertEqual(review([Hit("a", 1, "x stow y")], (one,)), [])
        self.assertTrue(review([Hit("a", 1, "x stow y")] * 2, (one,)))
        self.assertTrue(review([Hit("a", 0, "x stow y")], (Kept("a", "", 1, NEGATIVE, "why"),)))

    def test_allowlist_entries_name_their_kind_and_reason(self):
        self.assertEqual(len(set(KEPT)), len(KEPT))
        for entry in KEPT:
            self.assertIn(entry.kind, (RESIDUE, RECOVERY, NEGATIVE), entry)
            self.assertGreaterEqual(entry.count, 1, entry)
            self.assertTrue(entry.fragment and entry.why.strip(), entry)
        self.assertEqual([e.path for e in KEPT if e.kind == RECOVERY], ["README.md"])

    def test_tracked_files_name_no_retired_mechanism(self):
        problems = review(retired_hits(ROOT, tracked(ROOT)), KEPT)
        self.assertEqual(problems, [], "\n" + "\n".join(problems))


class MarkdownLinkTests(unittest.TestCase):
    def test_heading_slugs_follow_github(self):
        text = ("# T\n## Native configuration\n### H7-native: Reviewed native handover\n"
                "```sh\n# not a heading\n```\n## Native configuration\n## `persistentState` (2026-11-04)\n")
        self.assertEqual(heading_slugs(text), {"t", "native-configuration", "native-configuration-1",
                                               "h7-native-reviewed-native-handover",
                                               "persistentstate-2026-11-04"})

    def test_only_relative_links_outside_code_are_checked(self):
        text = ("[a](x.md#y) [web](https://example.org/z) [m](mailto:a@b)\n```\n[c](inside.md)\n```\n"
                "[wrapped\ntext](../z.md)\n")
        self.assertEqual(list(relative_links(text)), [(1, "x.md#y"), (5, "../z.md")])
        self.assertIsNone(resolve("README.md", "../outside.md"))
        self.assertEqual(resolve("docs/a.md", "../tests/COVERAGE.md"), "tests/COVERAGE.md")

    def test_missing_tracked_markdown_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a.md").write_text("[gone](gone.md)\n", encoding="utf-8")
            problems = broken_links(root, ["a.md", "gone.md"])
        self.assertEqual(problems, ["gone.md: tracked but missing from the work tree"])

    def test_tracked_markdown_links_and_anchors_resolve(self):
        problems = broken_links(ROOT, tracked(ROOT))
        self.assertEqual(problems, [], "\n" + "\n".join(problems))


if __name__ == "__main__":
    unittest.main()
