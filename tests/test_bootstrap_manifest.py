"""Validator for config/bootstrap, its docs parity and the bootstrap skills.

validate(config_dir, repo_root) returns "[rule] where: what" strings; an empty
list means valid. Standard library only, so it runs before any dependency is
installed. tests/bootstrap-manifest.sh runs this module; the Bash libraries in
lib/bootstrap/ trust the manifests it accepts.
"""
import fnmatch
import json
import re
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

KNOWN_HOSTS = ("mac", "wsl-ubuntu", "lab-ubuntu", "sherlock", "marlowe", "win")
HOST_PROFILE = {"mac": "macos", "wsl-ubuntu": "debian", "lab-ubuntu": "debian",
                "sherlock": "hpc", "marlowe": "hpc", "win": "windows"}
PROFILES = ("macos", "debian", "hpc", "windows")
TIERS = ("core", "cli", "ai", "desktop", "contributor", "host")
COVERED_TIERS = ("core", "cli", "ai")
VERSION_FLAGS = ("--version", "-V", "-v", "version", "-")
KINDS = ("script", "binary", "archive", "file")
ARCHES = ("any", "x86_64", "aarch64")
HUMANS = ("-", "sudo", "inspect")
TOKENS = ("$HOME", "$ZSH_CUSTOM", "$NVM_DIR", "$XDG_CONFIG_HOME", "$XDG_DATA_HOME", "$BAT_CONFIG_DIR")
STEP_IDS = (
    "P0-preflight", "H1-xcode-clt", "H1-homebrew", "H1-apt-core", "H1-locale", "H1-linuxbrew",
    "H1-gh-apt-repo", "H1-fcitx5", "S2-brew-bundle", "S2-micromamba", "H2-alloc", "S2-login-env",
    "S2-modules", "S3-clones", "S3-bat-theme", "S3-dirs", "S4-nvm", "S4-setup-sync", "S5-claude",
    "S5-codex", "S6-nerd-font", "S6-kitty", "H7-stow", "H7-chsh", "H7-auth", "H7-sync-skills",
    "H7-doctor", "W1-winget", "W1-psresources", "W1-font", "W1-bat-theme", "W1-setup-sync",
    "HW-clone", "HW-stow", "HW-auto-stow-task", "HW-execution-policy", "HW-ssh-agent", "HW-wsl",
    "HW-auth", "X-host-tools", "X-contributor", "X-other-linux", "X-rc-protection", "X-recovery")
RESERVED_IDS = ("locale", "venv-sync", "submodule", "stow-links", "path-order", "rc-pollution",
                "omz-order", "nvm-homebrew")
TOOLS_COLUMNS = ("id", "tier", "hosts", "probe", "version_flag", "floor", "absent", "doc")
CLONES_COLUMNS = ("id", "dest", "url", "ref", "hosts")
INSTALLERS_COLUMNS = ("id", "kind", "url", "sha256", "dest", "hosts", "arch", "tier", "human")
# Clone ids with their dests, and installer rows, as the bootstrap contract fixes them.
REQUIRED_CLONES = {"oh-my-zsh": "$HOME/.oh-my-zsh", "powerlevel10k": "$ZSH_CUSTOM/themes/powerlevel10k",
                   **{plugin: f"$ZSH_CUSTOM/plugins/{plugin}" for plugin in (
                       "fzf-tab", "fast-syntax-highlighting", "zsh-autosuggestions", "you-should-use",
                       "conda-zsh-completion", "zsh-completions")}}
INSTALLER_FIXED = ("kind", "hosts", "tier", "human", "dest", "url")  # url is an fnmatch glob
BREW_HOSTS, DEBIAN_HOSTS = "mac,wsl-ubuntu,lab-ubuntu", "wsl-ubuntu,lab-ubuntu"
GH, RAW = "https://github.com/", "https://raw.githubusercontent.com/"
REQUIRED_INSTALLERS = {
    ("homebrew", "any"): ("script", BREW_HOSTS, "core", "sudo", "-", RAW + "Homebrew/install/*/install.sh"),
    ("nvm", "any"): ("script", BREW_HOSTS, "ai", "-", "-", RAW + "nvm-sh/nvm/v*/install.sh"),
    ("claude", "any"): ("script", DEBIAN_HOSTS, "ai", "inspect", "-", "https://claude.ai/install.sh"),
    ("nerd-font", "any"): ("archive", "lab-ubuntu", "desktop", "-", "$XDG_DATA_HOME/fonts/CaskaydiaMonoNerdFont",
                           GH + "ryanoasis/nerd-fonts/releases/download/v*/CascadiaMono.tar.xz"),
    ("bat-theme", "any"): ("file", "all", "core", "-", "$BAT_CONFIG_DIR/themes/Catppuccin Mocha.tmTheme",
                           RAW + "catppuccin/bat/*/themes/Catppuccin%20Mocha.tmTheme")}
for _arch, _mamba, _kitty in (("x86_64", "64", "x86_64"), ("aarch64", "aarch64", "arm64")):
    REQUIRED_INSTALLERS[("micromamba", _arch)] = ("binary", "sherlock,marlowe", "core", "-", "$HOME/.local/bin/micromamba",
                                                  f"{GH}mamba-org/micromamba-releases/releases/download/*/micromamba-linux-{_mamba}")
    REQUIRED_INSTALLERS[("codex", _arch)] = ("archive", DEBIAN_HOSTS, "ai", "-", "$HOME/.codex/packages/standalone",
                                             f"{GH}openai/codex/releases/download/rust-v*/codex-package-{_arch}-unknown-linux-musl.tar.gz")
    REQUIRED_INSTALLERS[("kitty", _arch)] = ("archive", "lab-ubuntu", "desktop", "-", "$HOME/.local/kitty.app",
                                             f"{GH}kovidgoyal/kitty/releases/download/v*/kitty-*-{_kitty}.txz")
BREW_TIERS = ("core", "cli", "ai", "desktop", "contributor")
APT_COMMON = ("zsh", "git", "git-lfs", "curl", "rsync", "tar", "file", "procps", "build-essential",
              "gnupg", "python3", "python3-venv", "python3-pip", "tmux", "bsdextrautils", "man-db",
              "locales", "ca-certificates", "unzip", "xz-utils", "fontconfig")
APT_HOST_REQUIRED = {"wsl-ubuntu": ("wslu", "libnotify-bin"), "lab-ubuntu": ("xclip", "wl-clipboard", "fcitx5")}
LOGIN_REQUIRED = ("python", "zsh", "git", "git-lfs", "gh", "stow", "tmux", "rsync", "curl", "fzf",
                  "zoxide", "eza", "bat", "fd-find", "ripgrep", "nvim", "jq", "tealdeer", "aria2",
                  "uv", "go-shfmt", "shellcheck", "pre-commit", "file", "nodejs")
LOGIN_TRAPS = {"neovim": "nvim (conda-forge neovim is the Python client)", "fd": "fd-find",
               "shfmt": "go-shfmt", "delta": "git-delta"}
WINGET_REQUIRED = (
    "Microsoft.PowerShell", "Git.Git", "Python.Python.3.12", "OpenJS.NodeJS.LTS", "junegunn.fzf",
    "ajeetdsouza.zoxide", "eza-community.eza", "sharkdp.bat", "sharkdp.fd",
    "BurntSushi.ripgrep.MSVC", "dandavison.delta", "jqlang.jq", "Neovim.Neovim", "astral-sh.uv",
    "GitHub.cli", "JanDeDobbeleer.OhMyPosh", "Microsoft.WindowsTerminal", "wez.wezterm",
    "Anthropic.ClaudeCode", "OpenAI.Codex", "tldr-pages.tlrc", "aria2.aria2")
WINGET_SCHEMA = "https://aka.ms/winget-packages.schema.2.0.json"
SKILL_NAME = "dotfiles-bootstrap"
SKILL_CLAUDE = Path(".claude/skills") / SKILL_NAME / "SKILL.md"
SKILL_CODEX = Path(".agents/skills") / SKILL_NAME / "SKILL.md"
CODEX_KEYS = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}
CLAUDE_KEYS = CODEX_KEYS | {"disable-model-invocation"}

ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
FLOOR_RE = re.compile(r"^[0-9]+\.[0-9]+(\.[0-9]+)?$")
COMMAND_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*$")
FONT_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._-]*$")
ENV_RE = re.compile(r"^[A-Z_][A-Z0-9_]*$")
PSMODULE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
GITHUB_RE = re.compile(r"^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$")
PINNED_URL_RE = re.compile(r"/(?:[0-9a-f]{40}|(?:rust-)?v?[0-9]+\.[0-9]+[0-9A-Za-z.+-]*)/")
HEADING_RE = re.compile(r"^### ([A-Za-z0-9-]+):")
APT_RE = re.compile(r"^[a-z0-9][a-z0-9+.-]+$")
WINGET_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_+-]*(\.[A-Za-z0-9][A-Za-z0-9_+-]*)+$")
BREW_RE = re.compile(r'^(brew|cask) "([a-z0-9][a-z0-9@+._/-]*)"(?: if OS\.(mac|linux)\?)?$')
TAP_RE = re.compile(r'^tap "[a-z0-9_-]+/[a-z0-9_-]+"$')
DEP_RE = re.compile(r"^([a-z0-9][a-z0-9._-]*)((?:[<>=!~]=?[0-9][0-9a-z.*]*,?)*)$")
ALIAS_RE = re.compile(r"^# alias: ([a-z0-9][a-z0-9-]*) ([A-Za-z0-9@+._-]+)$")
MANUAL_RE = re.compile(r"^# manual: ([a-z0-9][a-z0-9-]*) ([a-z0-9-]+(?:,[a-z0-9-]+)*)$")
PINNED_RE = re.compile(r"^#.*\bpinned [0-9]{4}-[0-9]{2}-[0-9]{2}\b", re.MULTILINE)
HOME_RE = re.compile(r"/home/(?!linuxbrew(?:/|\b))[A-Za-z0-9._-]+|/users/|[a-z]:[\\/]+users\b", re.I)
SKILL_NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
CELL_FORBIDDEN = ("|", ";", "&", "$(", "`", "\r")
ABSENT_FORBIDDEN = CELL_FORBIDDEN + ("$", '"', "\\", "<", ">")


class Row(dict):
    """A TSV data row with its 1-based line number."""

    def __init__(self, line, cells):
        super().__init__(cells)
        self.line = line


def report(errors, rule, where, problem):
    """Record PROBLEM (a message, or a falsy value for none) under RULE."""
    if problem:
        errors.append(f"[{rule}] {where}: {problem}")


def expand_hosts(hosts):
    if hosts == "all":
        return list(KNOWN_HOSTS)
    if hosts == "unix":
        return [host for host in KNOWN_HOSTS if host != "win"]
    return hosts.split(",")


def hosts_error(hosts):
    if hosts in ("all", "unix"):
        return None
    parts = hosts.split(",")
    if any(part not in KNOWN_HOSTS for part in parts):
        return f"unknown host in {hosts!r}"
    return f"duplicate host in {hosts!r}" if len(set(parts)) != len(parts) else None


def path_error(path):
    """Return why a tokenized path is invalid, or None."""
    if path.startswith("$"):
        token = next((t for t in TOKENS if path == t or path.startswith(t + "/")), None)
        if token is None:
            return f"unsupported $ token in {path!r}"
        rest = path[len(token):]
    elif path.startswith("/"):
        rest = path
    else:
        return f"{path!r} is neither absolute nor token-prefixed"
    if "$" in rest:
        return f"only one leading token is allowed in {path!r}"
    if "~" in path:
        return f"~ is not allowed in {path!r}"
    return f".. is not allowed in {path!r}" if ".." in rest.split("/") else None


def probe_error(probe, hosts):
    kind, sep, value = probe.partition(":")
    if not sep:
        return None if all(COMMAND_RE.match(p) for p in probe.split(",")) else f"bad command probe {probe!r}"
    if kind in ("file", "dir"):
        return path_error(value)
    if kind == "font":
        return None if FONT_RE.match(value) else f"bad font family {value!r}"
    if kind == "env":
        return None if ENV_RE.match(value) else f"bad variable {value!r}"
    if kind == "psmodule":
        if hosts != "win":
            return "psmodule probes are Windows-only (hosts must be win)"
        return None if PSMODULE_RE.match(value) else f"bad module {value!r}"
    return f"unknown probe kind {kind!r}"


def read_text(path, rel, errors):
    try:
        return path.read_bytes().decode("utf-8")
    except FileNotFoundError:
        errors.append(f"[missing-file] {rel}: not found")
    except UnicodeDecodeError:
        errors.append(f"[tsv-format] {rel}: not UTF-8")
    return None


def read_tsv(path, rel, columns, errors):
    """Parse a manifest TSV. Returns (rows, comments as (line, text))."""
    text = read_text(path, rel, errors)
    if text is None:
        return [], []
    rows, comments, header = [], [], False
    lines = text.split("\n")
    if lines[-1] == "":
        lines.pop()
    for number, line in enumerate(lines, 1):
        where = f"{rel}:{number}"
        if line.startswith("#"):
            comments.append((number, line))
            continue
        cells = line.split("\t")
        if not line.strip():
            report(errors, "tsv-format", where, "blank line")
        elif not header:
            header = True
            report(errors, "tsv-format", where, tuple(cells) != columns and f"header must be {' '.join(columns)}")
        elif len(cells) != len(columns):
            report(errors, "tsv-format", where, f"{len(cells)} cells, expected {len(columns)} (trailing tab?)")
        elif any(cell == "" or cell != cell.strip() for cell in cells):
            report(errors, "tsv-format", where, "empty or padded cell (use - for n/a)")
        else:
            for column, cell in zip(columns, cells):
                bad = [c for c in (ABSENT_FORBIDDEN if column == "absent" else CELL_FORBIDDEN) if c in cell]
                report(errors, "cell-chars", where, bad and f"{column} contains {' '.join(bad)}")
            rows.append(Row(number, zip(columns, cells)))
    report(errors, "tsv-format", rel, not header and "no header row")
    return rows, comments


def check_unique(rows, key, rel, errors):
    seen = {}
    for row in rows:
        first = seen.setdefault(key(row), row.line)
        report(errors, "dup-id", f"{rel}:{row.line}", first != row.line and f"{key(row)} repeats line {first}")


def parse_declarations(comments, tool_ids, errors):
    aliases, manual = {}, {}
    for number, line in comments:
        if not line.startswith(("# alias:", "# manual:")):
            continue
        where = f"tools.tsv:{number}"
        alias, man = ALIAS_RE.match(line), MANUAL_RE.match(line)
        if not (alias or man):
            report(errors, "declaration", where, "expected '# alias: ID NAME' or '# manual: ID SCOPES'")
        elif (alias or man).group(1) not in tool_ids:
            report(errors, "declaration", where, f"unknown tool id {(alias or man).group(1)!r}")
        elif alias:
            aliases.setdefault(alias.group(1), set()).add(alias.group(2))
        else:
            scopes = man.group(2).split(",")
            unknown = [s for s in scopes if s not in KNOWN_HOSTS and s not in PROFILES]
            report(errors, "declaration", where, unknown and f"unknown scope {', '.join(unknown)}")
            manual.setdefault(man.group(1), set()).update(scopes)
    return aliases, manual


def check_tools(rows, errors):
    check_unique(rows, lambda r: r["id"], "tools.tsv", errors)
    for row in rows:
        where, flag, floor = f"tools.tsv:{row.line}", row["version_flag"], row["floor"]
        report(errors, "vocab", where, not ID_RE.match(row["id"]) and f"bad id {row['id']!r}")
        report(errors, "reserved-id", where, row["id"] in RESERVED_IDS and f"{row['id']} is a structural check")
        report(errors, "vocab", where, row["tier"] not in TIERS and f"unknown tier {row['tier']!r}")
        report(errors, "vocab", where, hosts_error(row["hosts"]))
        report(errors, "probe", where, probe_error(row["probe"], row["hosts"]))
        report(errors, "vocab", where, flag not in VERSION_FLAGS and f"unknown version_flag {flag!r}")
        report(errors, "floor", where, floor != "-" and not FLOOR_RE.match(floor) and f"floor {floor!r} is not X.Y[.Z]")
        presence = ":" in row["probe"] and (flag != "-" or floor != "-")
        report(errors, "probe-version", where, presence and "file, dir, font, env and psmodule probes are presence-only")
        report(errors, "probe-version", where, floor != "-" and flag == "-" and "a floor needs a version_flag")
        report(errors, "doc", where, row["doc"] not in STEP_IDS and f"unknown step id {row['doc']!r}")


def check_clones(rows, tools, errors):
    check_unique(rows, lambda r: r["id"], "git-clones.tsv", errors)
    for row in rows:
        where, ref = f"git-clones.tsv:{row.line}", row["ref"]
        report(errors, "clone-id", where, row["id"] not in tools and f"{row['id']} is not a tools.tsv id")
        report(errors, "clone-dest", where, path_error(row["dest"]))
        fixed = REQUIRED_CLONES.get(row["id"], row["dest"])
        report(errors, "clone-set", where, fixed != row["dest"] and f"{row['id']} dest must be {fixed}")
        report(errors, "clone-url", where, not GITHUB_RE.match(row["url"]) and "url must be https://github.com/O/R.git")
        if row["id"] == "oh-my-zsh":
            report(errors, "clone-ref", where, ref != "master" and "oh-my-zsh must track master (self-updating)")
        else:
            report(errors, "clone-ref", where, not COMMIT_RE.match(ref) and "ref must be a 40-hex commit")
        problem = hosts_error(row["hosts"])
        report(errors, "vocab", where, problem)
        windows = not problem and "win" in expand_hosts(row["hosts"])
        report(errors, "clone-hosts", where, windows and "clones are Unix-only (use unix or a list)")
        tool = tools.get(row["id"])
        target = tool["probe"].partition(":")[2] if tool and ":" in tool["probe"] else None
        outside = target is not None and not target.startswith(row["dest"] + "/")
        report(errors, "clone-probe", where, outside and f"tools.tsv probe {target!r} is not inside {row['dest']}")
    missing = sorted(set(REQUIRED_CLONES) - {row["id"] for row in rows})
    report(errors, "clone-set", "git-clones.tsv", missing and f"missing {', '.join(missing)}")


def check_installers(rows, tools, errors):
    check_unique(rows, lambda r: (r["id"], r["arch"]), "installers.tsv", errors)
    for row in rows:
        where, url, sha, dest = f"installers.tsv:{row.line}", row["url"], row["sha256"], row["dest"]
        report(errors, "installer-id", where, row["id"] not in tools and f"{row['id']} is not a tools.tsv id")
        for column, vocabulary in (("kind", KINDS), ("arch", ARCHES), ("tier", TIERS), ("human", HUMANS)):
            report(errors, "vocab", where, row[column] not in vocabulary and f"unknown {column} {row[column]!r}")
        report(errors, "vocab", where, hosts_error(row["hosts"]))
        bad_url = not url.startswith("https://") or " " in url
        report(errors, "installer-url", where, bad_url and "url must be https:// without spaces")
        if row["human"] == "inspect":
            report(errors, "sha256", where, sha != "-" and not SHA256_RE.match(sha) and "must be - or 64 lowercase hex")
        else:
            report(errors, "sha256", where, not SHA256_RE.match(sha) and "must be 64 lowercase hex (- only for inspect)")
            report(errors, "installer-pin", where, not PINNED_URL_RE.search(url) and "url must name a commit or version")
        if row["kind"] == "script":
            report(errors, "installer-dest", where, dest != "-" and "scripts have dest -")
        else:
            report(errors, "installer-dest", where, "dest - is only for scripts" if dest == "-" else path_error(dest))
    present = {(row["id"], row["arch"]): row for row in rows}
    missing = [f"{i}/{a}" for i, a in REQUIRED_INSTALLERS if (i, a) not in present]
    report(errors, "installer-set", "installers.tsv", missing and f"missing {', '.join(missing)}")
    for key, expected in REQUIRED_INSTALLERS.items():
        row = present.get(key)
        if row is None:
            continue
        wrong = [f"{column} {row[column]!r}, expected {value!r}" for column, value in zip(INSTALLER_FIXED, expected)
                 if not (fnmatch.fnmatchcase(row[column], value) if column == "url" else row[column] == value)]
        report(errors, "installer-set", f"installers.tsv:{row.line}", wrong and f"{'/'.join(key)}: {'; '.join(wrong)}")
        digest = expected[3] == "inspect" and row["sha256"] != "-"
        report(errors, "installer-set", f"installers.tsv:{row.line}", digest and "an unpinnable inspect download has sha256 -")


def read_brewfiles(config, errors):
    """Return [(name, os_guard)] across all tier Brewfiles."""
    entries, seen = [], {}
    for tier in BREW_TIERS:
        rel = f"brew/{tier}.Brewfile"
        for number, line in enumerate((read_text(config / rel, rel, errors) or "").splitlines(), 1):
            where, match = f"{rel}:{number}", BREW_RE.match(line)
            if line == "" or line.startswith("#") or TAP_RE.match(line):
                continue
            if not match:
                report(errors, "brewfile", where, 'not brew "x", cask "x" if OS.mac?, tap or a comment')
                continue
            kind, name, guard = match.groups()
            base = name.rsplit("/", 1)[-1]
            report(errors, "brewfile", where, kind == "cask" and guard != "mac" and "casks need if OS.mac?")
            forbidden = base in ("nvm", "openssh") or base.startswith("openssh@")
            report(errors, "brewfile-forbidden", where, forbidden and f"{base} must never be bundled")
            report(errors, "brewfile", where, name in seen and f"{name} repeats {seen.get(name)}")
            seen[name] = where
            entries.append((name, guard))
    return entries


def read_apt(config, errors):
    lists = {}
    for name in ("common",) + tuple(APT_HOST_REQUIRED):
        rel, packages = f"apt/{name}.txt", []
        for number, line in enumerate((read_text(config / rel, rel, errors) or "").splitlines(), 1):
            if line == "" or line.startswith("#"):
                continue
            if not APT_RE.match(line):
                report(errors, "apt", f"{rel}:{number}", f"{line!r} is not a bare package name")
            elif line in packages:
                report(errors, "apt", f"{rel}:{number}", f"{line} repeats")
            else:
                packages.append(line)
        lists[name] = packages
    extra, missing = sorted(set(lists["common"]) - set(APT_COMMON)), sorted(set(APT_COMMON) - set(lists["common"]))
    report(errors, "apt-set", "apt/common.txt", (extra or missing) and f"missing {missing}, unexpected {extra}")
    for host, required in APT_HOST_REQUIRED.items():
        missing = sorted(set(required) - set(lists[host]))
        report(errors, "apt-set", f"apt/{host}.txt", missing and f"missing {', '.join(missing)}")
        overlap = sorted(set(lists[host]) & set(lists["common"]))
        report(errors, "apt", f"apt/{host}.txt", overlap and f"already in common.txt: {', '.join(overlap)}")
    return lists


def read_login_env(config, errors):
    """Parse the restricted YAML of hpc-login-env.yml into (name, channels, deps)."""
    rel = "hpc-login-env.yml"
    name, lists, section = None, {"channels": [], "dependencies": []}, None
    for number, raw in enumerate((read_text(config / rel, rel, errors) or "").splitlines(), 1):
        where, line = f"{rel}:{number}", raw.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        if raw[0].isspace():
            item = line.strip()
            if section is None or not item.startswith("- "):
                report(errors, "yml", where, "expected a '- item' under channels or dependencies")
            else:
                lists[section].append((number, item[2:].strip()))
            continue
        key, sep, value = line.partition(":")
        value, section = value.strip(), None
        if not sep or key not in ("name", "channels", "dependencies"):
            report(errors, "yml", where, "only name, channels and dependencies are allowed")
        elif key == "name":
            name = value
        elif value.startswith("[") and value.endswith("]"):
            lists[key].extend((number, v.strip()) for v in value[1:-1].split(",") if v.strip())
        elif value:
            report(errors, "yml", where, f"{key} must be a list")
        else:
            section = key
    return name, [c for _, c in lists["channels"]], lists["dependencies"]


def check_login_env(config, tools, aliases, errors):
    rel = "hpc-login-env.yml"
    name, channels, deps = read_login_env(config, errors)
    report(errors, "yml", rel, name != "login" and "name must be login")
    report(errors, "yml", rel, channels != ["conda-forge"] and "channels must be exactly [conda-forge]")
    names = {}
    for number, dep in deps:
        where, match = f"{rel}:{number}", DEP_RE.match(dep)
        if not match:
            report(errors, "yml", where, f"bad dependency {dep!r}")
            continue
        package, spec = match.groups()
        report(errors, "yml", where, package in names and f"{package} repeats")
        names[package] = spec
        report(errors, "yml-trap", where, package in LOGIN_TRAPS and f"use {LOGIN_TRAPS.get(package)} for {package}")
        tool = next((t for t in tools.values() if package in {t["id"]} | aliases.get(t["id"], set())), None)
        floor = tool["floor"] if tool else "-"
        report(errors, "yml-floor", where, floor != "-" and spec != f">={floor}" and f"{package} needs >={floor}")
    missing = sorted(set(LOGIN_REQUIRED) - set(names))
    report(errors, "yml-set", rel, missing and f"missing {', '.join(missing)}")
    return set(names) | ({name} if name else set())


def read_winget(config, errors):
    rel, ids = "winget.json", []
    text = read_text(config / rel, rel, errors)
    try:
        data = json.loads(text) if text is not None else {}
    except json.JSONDecodeError as error:
        report(errors, "winget", rel, f"invalid JSON ({error.msg})")
        return set()
    if text is None or not isinstance(data, dict) or data.get("$schema") != WINGET_SCHEMA:
        report(errors, "winget", rel, text is not None and f"$schema must be {WINGET_SCHEMA}")
        return set()
    report(errors, "winget", rel, not isinstance(data.get("CreationDate"), str) and "CreationDate is required")
    sources = data.get("Sources") if isinstance(data.get("Sources"), list) else []
    report(errors, "winget", rel, not sources and "Sources must be a non-empty list")
    keys = ("Name", "Identifier", "Argument", "Type")
    for index, source in enumerate(s if isinstance(s, dict) else {} for s in sources):
        details = source.get("SourceDetails") if isinstance(source.get("SourceDetails"), dict) else {}
        bad = not all(isinstance(details.get(k), str) for k in keys)
        report(errors, "winget", rel, bad and f"Sources[{index}].SourceDetails needs {', '.join(keys)}")
        packages = source.get("Packages") if isinstance(source.get("Packages"), list) else []
        report(errors, "winget", rel, not packages and f"Sources[{index}].Packages must be a non-empty list")
        for package in packages:
            identifier = package.get("PackageIdentifier") if isinstance(package, dict) else None
            if not isinstance(identifier, str) or not WINGET_ID_RE.match(identifier):
                report(errors, "winget", rel, f"bad PackageIdentifier {identifier!r}")
            elif identifier in ids:
                report(errors, "winget", rel, f"{identifier} repeats")
            else:
                ids.append(identifier)
    named = any(isinstance(s, dict) and isinstance(s.get("SourceDetails"), dict)
                and s["SourceDetails"].get("Name") == "winget" for s in sources)
    report(errors, "winget", rel, sources and not named and "no source named winget")
    missing = sorted(set(WINGET_REQUIRED) - set(ids))
    report(errors, "winget-set", rel, missing and f"missing {', '.join(missing)}")
    return set(ids)


def host_sources(host, brew, apt, login, winget, clones, installers):
    profile = HOST_PROFILE[host]
    names = {r["id"] for r in clones + installers if not hosts_error(r["hosts"]) and host in expand_hosts(r["hosts"])}
    if profile == "macos":
        names |= {name for name, guard in brew if guard != "linux"}
    elif profile == "debian":
        names |= {name for name, guard in brew if guard != "mac"}
        names |= set(apt.get("common", ())) | set(apt.get(host, ()))
    return names | (login if profile == "hpc" else set()) | (winget if profile == "windows" else set())


def check_coverage(tools, aliases, manual, sources, errors):
    for row in tools.values():
        if row["tier"] not in COVERED_TIERS or hosts_error(row["hosts"]):
            continue
        names, scopes = {row["id"]} | aliases.get(row["id"], set()), manual.get(row["id"], set())
        for host in expand_hosts(row["hosts"]):
            covered = names & sources[host] or host in scopes or HOST_PROFILE[host] in scopes
            report(errors, "coverage", f"tools.tsv:{row.line}", not covered and
                   f"no manifest installs {row['id']} on {host}; add it, or declare '# alias:' or '# manual:'")


def check_file_text(config, errors):
    for path in sorted(p for p in config.rglob("*") if p.is_file()):
        rel = path.relative_to(config).as_posix()
        text = read_text(path, rel, errors) or ""
        for number, line in enumerate(text.splitlines(), 1):
            report(errors, "home-literal", f"{rel}:{number}", HOME_RE.search(line) and "machine-specific home path")
        missing = path.suffix != ".json" and not PINNED_RE.search(text)
        report(errors, "pinned-header", rel, missing and "needs a '# pinned YYYY-MM-DD' comment")


def check_docs(repo, tools, errors):
    text = read_text(repo / "docs/bootstrap.md", "docs/bootstrap.md", errors) or ""
    found = [m.group(1) for m in map(HEADING_RE.match, text.splitlines()) if m]
    for step in STEP_IDS:
        count = found.count(step)
        report(errors, "docs-headings", "docs/bootstrap.md", count != 1 and f"{count} '### {step}:' headings, expected 1")
    for step in sorted(set(found) - set(STEP_IDS)):
        report(errors, "docs-headings", "docs/bootstrap.md", f"'### {step}:' is not a contract step id")
    text = read_text(repo / "docs/dependencies.md", "docs/dependencies.md", errors) or ""
    cells = {cell.strip().strip("`") for line in text.splitlines() if line.startswith("|")
             for cell in line.strip("|").split("|")}
    for row in tools.values():
        report(errors, "docs-deps", "docs/dependencies.md", row["id"] not in cells and f"no table cell for {row['id']}")


def split_skill(path, rel, errors):
    text = read_text(path, rel, errors)
    if text is None or not text.startswith("---\n") or "\n---\n" not in text[3:]:
        report(errors, "skill", rel, text is not None and "missing --- frontmatter")
        return None, None
    end, keys = text.index("\n---\n", 3), {}
    for line in text[4:end].splitlines():
        if not line.strip() or line[0].isspace() or line.lstrip().startswith("#"):
            continue
        key, sep, value = line.partition(":")
        report(errors, "skill", rel, not sep and f"bad frontmatter line {line!r}")
        keys[key.strip()] = value.strip()
    return keys, text[end + 5:]


def check_skills(repo, errors):
    claude, claude_body = split_skill(repo / SKILL_CLAUDE, SKILL_CLAUDE.as_posix(), errors)
    codex, codex_body = split_skill(repo / SKILL_CODEX, SKILL_CODEX.as_posix(), errors)
    for rel, keys, allowed in ((SKILL_CLAUDE, claude, CLAUDE_KEYS), (SKILL_CODEX, codex, CODEX_KEYS)):
        where, name, extra = rel.as_posix(), (keys or {}).get("name", ""), sorted(set(keys or {}) - allowed)
        if keys is None:
            continue
        bad_name = name != rel.parent.name or not SKILL_NAME_RE.match(name)
        report(errors, "skill", where, bad_name and f"name must equal the directory name {rel.parent.name}")
        report(errors, "skill", where, not 0 < len(keys.get("description", "")) <= 1024 and "description is 1-1024 chars")
        report(errors, "skill", where, len(keys.get("compatibility", "")) > 500 and "compatibility is over 500 chars")
        report(errors, "skill", where, extra and f"frontmatter keys not allowed: {', '.join(extra)}")
    flagged = claude is None or claude.get("disable-model-invocation") == "true"
    report(errors, "skill", SKILL_CLAUDE.as_posix(), not flagged and "needs disable-model-invocation: true")
    differ = claude_body is not None and codex_body is not None and claude_body != codex_body
    report(errors, "skill", "SKILL.md", differ and "bodies differ between .claude/skills and .agents/skills")


def validate(config_dir, repo_root):
    """Return every rule violation in config_dir, docs and skills under repo_root."""
    config, repo, errors = Path(config_dir), Path(repo_root), []
    tool_rows, comments = read_tsv(config / "tools.tsv", "tools.tsv", TOOLS_COLUMNS, errors)
    clone_rows, _ = read_tsv(config / "git-clones.tsv", "git-clones.tsv", CLONES_COLUMNS, errors)
    installer_rows, _ = read_tsv(config / "installers.tsv", "installers.tsv", INSTALLERS_COLUMNS, errors)
    check_tools(tool_rows, errors)
    tools = {}
    for row in tool_rows:
        tools.setdefault(row["id"], row)
    aliases, manual = parse_declarations(comments, tools, errors)
    check_clones(clone_rows, tools, errors)
    check_installers(installer_rows, tools, errors)
    brew, apt = read_brewfiles(config, errors), read_apt(config, errors)
    login, winget = check_login_env(config, tools, aliases, errors), read_winget(config, errors)
    sources = {host: host_sources(host, brew, apt, login, winget, clone_rows, installer_rows) for host in KNOWN_HOSTS}
    check_coverage(tools, aliases, manual, sources, errors)
    check_file_text(config, errors)
    check_docs(repo, tools, errors)
    check_skills(repo, errors)
    return errors


class RepositoryManifestTests(unittest.TestCase):
    def test_repository_manifests_docs_and_skills_are_valid(self):
        self.assertEqual(validate(ROOT / "config/bootstrap", ROOT), [])


class RejectionTests(unittest.TestCase):
    """Each (rule, case, mutation) breaks a fresh copy of the real files and expects its rule to fire."""

    def setUp(self):
        self.temp = Path(tempfile.mkdtemp(prefix="bootstrap-manifest-"))
        self.addCleanup(shutil.rmtree, self.temp)
        self.repo = self.temp / "repo"
        self.config = self.repo / "config/bootstrap"
        shutil.copytree(ROOT / "config/bootstrap", self.config)
        for rel in ("docs/bootstrap.md", "docs/dependencies.md", SKILL_CLAUDE, SKILL_CODEX):
            (self.repo / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / rel, self.repo / rel)
        self.assertEqual(self.errors(), [])

    def errors(self):
        return validate(self.config, self.repo)

    def path(self, rel):
        return self.repo / rel if str(rel).startswith((".", "docs")) else self.config / rel

    def replace(self, rel, old, new):
        path = self.path(rel)
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text, f"fixture text missing from {rel}")
        path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="")

    def append(self, rel, text):
        with self.path(rel).open("a", encoding="utf-8", newline="") as handle:
            handle.write(text)

    def row(self, rel, row_id):
        for line in self.path(rel).read_text(encoding="utf-8").splitlines():
            if line.startswith(row_id + "\t"):
                return line
        self.fail(f"no {row_id} row in {rel}")

    def set_cell(self, rel, row_id, column, value, columns):
        """Set a cell of ROW_ID's first row to VALUE, or to VALUE(old cell) when VALUE is callable."""
        old = self.row(rel, row_id)
        cells = old.split("\t")
        index = columns.index(column)
        cells[index] = value(cells[index]) if callable(value) else value
        self.replace(rel, old, "\t".join(cells))

    def check(self, cases):
        for rule, name, mutate in cases:
            with self.subTest(f"{rule}: {name}"):
                self.setUp()
                mutate()
                errors = self.errors()
                self.assertTrue(any(e.startswith(f"[{rule}]") for e in errors), f"{name}: {rule} not in {errors}")

    def tools(self, *cell):
        return lambda: self.set_cell("tools.tsv", *cell, TOOLS_COLUMNS)

    def clones(self, *cell):
        return lambda: self.set_cell("git-clones.tsv", *cell, CLONES_COLUMNS)

    def installers(self, *cell):
        return lambda: self.set_cell("installers.tsv", *cell, INSTALLERS_COLUMNS)

    def test_tsv_structure(self):
        fzf = "fzf\tcore\tall\tfzf\t--version\t0.58.0\tbroken\tS2-brew-bundle"
        self.check([
            ("tsv-format", "header", lambda: self.replace("tools.tsv", "id\ttier\thosts", "id\ttiers\thosts")),
            ("tsv-format", "trailing tab", lambda: self.replace("tools.tsv", self.row("tools.tsv", "fzf"), fzf + "\t")),
            ("tsv-format", "empty cell",
             lambda: self.replace("tools.tsv", self.row("tools.tsv", "fzf"), fzf.replace("0.58.0", ""))),
            ("tsv-format", "blank line", lambda: self.append("tools.tsv", "\n\n")),
            ("missing-file", "winget", lambda: (self.config / "winget.json").unlink()),
            ("dup-id", "tools", lambda: self.append("tools.tsv", self.row("tools.tsv", "fzf") + "\n")),
            ("dup-id", "clones", lambda: self.append("git-clones.tsv", self.row("git-clones.tsv", "fzf-tab") + "\n")),
            ("dup-id", "installer arch", lambda: self.append("installers.tsv", self.row("installers.tsv", "nvm") + "\n")),
        ])

    def test_vocabularies(self):
        self.check([
            ("vocab", "tier", self.tools("fzf", "tier", "essential")),
            ("vocab", "host", self.tools("fzf", "hosts", "mac,ubuntu")),
            ("vocab", "duplicate host", self.tools("kitty", "hosts", "mac,mac")),
            ("vocab", "version flag", self.tools("fzf", "version_flag", "--ver")),
            ("vocab", "id", self.tools("fzf", "id", "Fzf")),
            ("vocab", "installer kind", self.installers("nvm", "kind", "pipe")),
            ("vocab", "installer arch", self.installers("nvm", "arch", "arm64")),
            ("vocab", "installer human", self.installers("nvm", "human", "maybe")),
            ("reserved-id", "locale", self.tools("fzf", "id", "locale")),
        ])

    def test_probes_versions_and_floors(self):
        self.check([
            ("probe", "unknown token", self.tools("oh-my-zsh", "probe", "file:$FOO/x")),
            ("probe", "second token", self.tools("oh-my-zsh", "probe", "file:$HOME/$HOME/x")),
            ("probe", "tilde", self.tools("oh-my-zsh", "probe", "file:~/.oh-my-zsh/oh-my-zsh.sh")),
            ("probe", "dotdot", self.tools("oh-my-zsh", "probe", "file:$HOME/../x")),
            ("probe", "relative", self.tools("oh-my-zsh", "probe", "file:.oh-my-zsh")),
            ("probe", "kind", self.tools("oh-my-zsh", "probe", "url:https")),
            ("probe", "command", self.tools("fzf", "probe", "fzf --bin")),
            ("probe", "psmodule host", self.tools("psfzf", "hosts", "all")),
            ("probe", "env", self.tools("lmod", "probe", "env:lmod-dir")),
            ("floor", "floor", self.tools("fzf", "floor", "0.58.x")),
            ("probe-version", "presence with flag", self.tools("oh-my-zsh", "version_flag", "--version")),
            ("probe-version", "floor without flag", self.tools("fzf", "version_flag", "-")),
        ])

    def test_doc_ids_and_headings(self):
        self.check([
            ("doc", "unknown step", self.tools("fzf", "doc", "S3-bat-cache")),
            ("docs-headings", "missing", lambda: self.replace("docs/bootstrap.md", "### S3-clones:", "### S3 clones:")),
            ("docs-headings", "duplicate", lambda: self.append("docs/bootstrap.md", "\n### S3-clones: again\n")),
            ("docs-headings", "unknown", lambda: self.append("docs/bootstrap.md", "\n### S3-bat-cache: stale\n")),
            ("docs-deps", "missing id", lambda: self.replace("docs/dependencies.md", "| `fzf-tab` |", "| fzf tab |")),
        ])

    def test_clones(self):
        self.check([
            ("clone-id", "unknown id", self.clones("fzf-tab", "id", "fzf-tabs")),
            ("clone-ref", "branch", self.clones("fzf-tab", "ref", "master")),
            ("clone-ref", "short sha", self.clones("fzf-tab", "ref", "d7e0234")),
            ("clone-ref", "omz pinned", self.clones("oh-my-zsh", "ref", "42a4ccb1b14dbeffe81259105a5243b4f4cb618e")),
            ("clone-url", "not github .git", self.clones("fzf-tab", "url", "https://gitlab.com/a/b")),
            ("clone-hosts", "windows", self.clones("fzf-tab", "hosts", "all")),
            ("clone-dest", "token", self.clones("fzf-tab", "dest", "$ZSH/custom/plugins/fzf-tab")),
            ("clone-probe", "moved", self.clones("fzf-tab", "dest", "$ZSH_CUSTOM/plugins/tab")),
            ("clone-set", "missing",
             lambda: self.replace("git-clones.tsv", self.row("git-clones.tsv", "zsh-completions") + "\n", "")),
            ("clone-set", "dest", self.clones("powerlevel10k", "dest", "$ZSH_CUSTOM/plugins/powerlevel10k")),
        ])

    def test_installers(self):
        upper = "48A0EEE9A60E07422DCE0EB5774754C83889570CA1EE2566C516ACBE8AF03A9E"
        self.check([
            ("sha256", "dash without inspect", self.installers("nvm", "sha256", "-")),
            ("sha256", "uppercase", self.installers("nvm", "sha256", upper)),
            ("sha256", "short", self.installers("nvm", "sha256", "48a0eee9")),
            ("installer-pin", "branch url",
             self.installers("nvm", "url", "https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh")),
            ("installer-url", "http", self.installers("nvm", "url", "http://example.com/v1.0/x.sh")),
            ("installer-dest", "script dest", self.installers("nvm", "dest", "$HOME/nvm.sh")),
            ("installer-dest", "archive without dest", self.installers("nerd-font", "dest", "-")),
            ("installer-dest", "bad token", self.installers("nerd-font", "dest", "$FONTS/x")),
            ("installer-id", "unknown", self.installers("nvm", "id", "nvm-sh")),
            ("installer-set", "missing", lambda: self.replace("installers.tsv", self.row("installers.tsv", "claude") + "\n", "")),
            ("installer-set", "claude not inspect", lambda: (self.installers("claude", "human", "-")(),
                                                             self.installers("claude", "sha256", "a" * 64)())),
            ("installer-set", "claude digest", self.installers("claude", "sha256", "a" * 64)),
            ("installer-set", "homebrew without sudo", self.installers("homebrew", "human", "-")),
            ("installer-set", "micromamba hosts", self.installers("micromamba", "hosts", "unix")),
            ("installer-set", "micromamba tier", self.installers("micromamba", "tier", "host")),
            ("installer-set", "codex bare binary dest", self.installers("codex", "dest", "$HOME/.local/bin/codex")),
            ("installer-set", "codex bare binary asset",
             self.installers("codex", "url", lambda url: url.replace("codex-package-", "codex-"))),
            ("installer-set", "codex glibc asset", self.installers("codex", "url", lambda url: url.replace("musl", "gnu"))),
            ("installer-set", "kitty arch asset", self.installers("kitty", "url", lambda url: url.replace("x86_64", "arm64"))),
            ("installer-set", "nerd-font dest", self.installers("nerd-font", "dest", "$XDG_DATA_HOME/fonts")),
            ("installer-set", "bat-theme kind", self.installers("bat-theme", "kind", "archive")),
        ])

    def test_forbidden_characters_and_home_literals(self):
        self.check([
            ("cell-chars", "semicolon", self.tools("fzf", "absent", "fails; badly")),
            ("cell-chars", "pipe", self.tools("fzf", "absent", "fails | badly")),
            ("cell-chars", "ampersand", self.tools("fzf", "absent", "fails & badly")),
            ("cell-chars", "dollar paren", self.tools("fzf", "probe", "file:$HOME/$(id)")),
            ("cell-chars", "backtick", self.tools("fzf", "absent", "fails `x`")),
            ("cell-chars", "dollar in absent", self.tools("fzf", "absent", "fails at $HOME")),
            ("home-literal", "linux home", lambda: self.append("tools.tsv", "# see /home/alice/x\n")),
            ("home-literal", "mac home", lambda: self.append("apt/common.txt", "# /Users/alice\n")),
            ("home-literal", "cluster home", lambda: self.append("hpc-login-env.yml", "# /users/alice\n")),
            ("home-literal", "windows home", lambda: self.append("brew/core.Brewfile", "# C:\\Users\\alice\n")),
            ("pinned-header", "missing", lambda: self.replace("apt/wsl-ubuntu.txt", "# pinned", "# fixed")),
        ])

    def test_brewfiles_and_apt_lists(self):
        self.check([
            ("brewfile-forbidden", "openssh", lambda: self.append("brew/core.Brewfile", 'brew "openssh"\n')),
            ("brewfile-forbidden", "nvm", lambda: self.append("brew/ai.Brewfile", 'brew "nvm"\n')),
            ("brewfile", "ruby", lambda: self.append("brew/cli.Brewfile", 'system "curl x | sh"\n')),
            ("brewfile", "options", lambda: self.append("brew/cli.Brewfile", 'brew "jq", args: ["HEAD"]\n')),
            ("brewfile", "unguarded cask", lambda: self.append("brew/desktop.Brewfile", 'cask "iterm2"\n')),
            ("brewfile", "repeat", lambda: self.append("brew/contributor.Brewfile", 'brew "fzf"\n')),
            ("apt", "version", lambda: self.append("apt/lab-ubuntu.txt", "zsh=5.9\n")),
            ("apt", "trailing comment", lambda: self.append("apt/wsl-ubuntu.txt", "jq # json\n")),
            ("apt", "overlap", lambda: self.append("apt/lab-ubuntu.txt", "tmux\n")),
            ("apt-set", "common extra", lambda: self.append("apt/common.txt", "jq\n")),
            ("apt-set", "host missing", lambda: self.replace("apt/lab-ubuntu.txt", "xclip\n", "")),
            ("apt-set", "wsl host missing", lambda: self.replace("apt/wsl-ubuntu.txt", "wslu\n", "")),
        ])

    def test_winget_and_login_env(self):
        jq = '"PackageIdentifier": "jqlang.jq"'
        self.check([
            ("winget", "json", lambda: self.append("winget.json", "}")),
            ("winget", "schema", lambda: self.replace("winget.json", "schema.2.0", "schema.1.0")),
            ("winget", "source details", lambda: self.replace("winget.json", '"SourceDetails"', '"Details"')),
            ("winget", "package id", lambda: self.replace("winget.json", jq, '"Id": "jq"')),
            ("winget-set", "dropped", lambda: self.replace("winget.json", jq, '"PackageIdentifier": "stedolan.jq"')),
            ("yml-set", "missing", lambda: self.replace("hpc-login-env.yml", "  - tealdeer\n", "")),
            ("yml-set", "nodejs", lambda: self.replace("hpc-login-env.yml", "  - nodejs>=22.0\n", "")),
            ("yml-trap", "neovim", lambda: self.replace("hpc-login-env.yml", "  - nvim\n", "  - neovim\n")),
            ("yml-floor", "floor", lambda: self.replace("hpc-login-env.yml", "fzf>=0.58.0", "fzf>=0.44")),
            ("yml-floor", "node floor", lambda: self.replace("hpc-login-env.yml", "nodejs>=22.0", "nodejs>=18.0")),
            ("yml", "channel", lambda: self.replace("hpc-login-env.yml", "  - conda-forge\n", "  - defaults\n")),
            ("yml", "key", lambda: self.append("hpc-login-env.yml", "prefix: /opt/login\n")),
        ])

    def test_skills(self):
        self.check([
            ("skill", "body", lambda: self.append(SKILL_CODEX, "Extra line.\n")),
            ("skill", "name", lambda: self.replace(SKILL_CLAUDE, "name: dotfiles-bootstrap", "name: bootstrap")),
            ("skill", "codex key", lambda: self.replace(SKILL_CODEX, "metadata:", "disable-model-invocation: true\nmetadata:")),
            ("skill", "claude flag", lambda: self.replace(SKILL_CLAUDE, "disable-model-invocation: true\n", "")),
            ("skill", "frontmatter", lambda: self.replace(SKILL_CODEX, "---\nname", "name")),
        ])

    def test_coverage_and_declarations(self):
        self.check([
            ("coverage", "alias removed", lambda: self.replace("tools.tsv", "# alias: fzf junegunn.fzf\n", "")),
            ("coverage", "manual removed", lambda: self.replace("tools.tsv", "# manual: claude hpc\n", "")),
            ("coverage", "brew entry removed", lambda: self.replace("brew/cli.Brewfile", 'brew "jq"\n', "")),
            ("coverage", "login node removed", lambda: self.replace("tools.tsv", "# alias: node nodejs\n", "")),
            ("declaration", "malformed", lambda: self.append("tools.tsv", "# alias: fzf\n")),
            ("declaration", "unknown id", lambda: self.append("tools.tsv", "# alias: fzz junegunn.fzf\n")),
            ("declaration", "unknown scope", lambda: self.append("tools.tsv", "# manual: claude cluster\n")),
        ])


if __name__ == "__main__":
    unittest.main()
