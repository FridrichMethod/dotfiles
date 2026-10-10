"""Validator for config/bootstrap, its docs parity and the bootstrap skills.

validate(config_dir, repo_root) returns "[rule] where: what" strings; an empty
list means valid. Standard library only, so it runs before any dependency is
installed. tests/bootstrap-manifest.sh runs this module; the Bash libraries in
lib/bootstrap/ trust the manifests it accepts.
"""
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
REQUIRED_CLONES = ("oh-my-zsh", "powerlevel10k", "fzf-tab", "fast-syntax-highlighting",
                   "zsh-autosuggestions", "you-should-use", "conda-zsh-completion", "zsh-completions")
REQUIRED_INSTALLERS = (("homebrew", "any"), ("nvm", "any"), ("micromamba", "x86_64"),
                       ("micromamba", "aarch64"), ("codex", "x86_64"), ("codex", "aarch64"),
                       ("claude", "any"), ("nerd-font", "any"), ("kitty", "x86_64"),
                       ("kitty", "aarch64"), ("bat-theme", "any"))
BREW_TIERS = ("core", "cli", "ai", "desktop", "contributor")
APT_COMMON = ("zsh", "git", "git-lfs", "curl", "rsync", "tar", "file", "procps", "build-essential",
              "gnupg", "python3", "python3-venv", "python3-pip", "tmux", "bsdextrautils", "man-db",
              "locales", "ca-certificates", "unzip", "xz-utils", "fontconfig")
APT_HOST_REQUIRED = {"wsl-ubuntu": ("wslu", "libnotify-bin"),
                     "lab-ubuntu": ("xclip", "wl-clipboard", "fcitx5")}
LOGIN_REQUIRED = ("python", "zsh", "git", "git-lfs", "gh", "stow", "tmux", "rsync", "curl", "fzf",
                  "zoxide", "eza", "bat", "fd-find", "ripgrep", "nvim", "jq", "tealdeer", "aria2",
                  "uv", "go-shfmt", "shellcheck", "pre-commit", "file")
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


def expand_hosts(hosts):
    if hosts == "all":
        return list(KNOWN_HOSTS)
    if hosts == "unix":
        return [host for host in KNOWN_HOSTS if host != "win"]
    return hosts.split(",")


def host_matches(hosts, host):
    return host in expand_hosts(hosts)


def hosts_error(hosts):
    if hosts in ("all", "unix"):
        return None
    parts = hosts.split(",")
    if any(part not in KNOWN_HOSTS for part in parts):
        return f"unknown host in {hosts!r}"
    if len(set(parts)) != len(parts):
        return f"duplicate host in {hosts!r}"
    return None


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
    if ".." in rest.split("/"):
        return f".. is not allowed in {path!r}"
    return None


def probe_error(probe, hosts):
    kind, sep, value = probe.partition(":")
    if not sep:
        if all(COMMAND_RE.match(part) for part in probe.split(",")):
            return None
        return f"bad command probe {probe!r}"
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
    for number, line in enumerate(text.split("\n"), 1):
        where = f"{rel}:{number}"
        if line == "" and number == text.count("\n") + 1:
            break
        if line.startswith("#"):
            comments.append((number, line))
            continue
        if not line.strip():
            errors.append(f"[tsv-format] {where}: blank line")
            continue
        cells = line.split("\t")
        if not header:
            header = True
            if tuple(cells) != columns:
                errors.append(f"[tsv-format] {where}: header must be {' '.join(columns)}")
            continue
        if len(cells) != len(columns):
            errors.append(f"[tsv-format] {where}: {len(cells)} cells, expected {len(columns)}"
                          " (trailing tab or missing cell)")
            continue
        if any(cell == "" or cell != cell.strip() for cell in cells):
            errors.append(f"[tsv-format] {where}: empty or padded cell (use - for n/a)")
            continue
        for column, cell in zip(columns, cells):
            bad = [c for c in (ABSENT_FORBIDDEN if column == "absent" else CELL_FORBIDDEN) if c in cell]
            if bad:
                errors.append(f"[cell-chars] {where}: {column} contains {' '.join(bad)}")
        rows.append(Row(number, zip(columns, cells)))
    if not header:
        errors.append(f"[tsv-format] {rel}: no header row")
    return rows, comments


def check_unique(rows, key, rel, errors, rule="dup-id"):
    seen = {}
    for row in rows:
        value = key(row)
        if value in seen:
            errors.append(f"[{rule}] {rel}:{row.line}: {value} repeats line {seen[value]}")
        else:
            seen[value] = row.line


def parse_declarations(comments, tool_ids, errors):
    aliases, manual = {}, {}
    for number, line in comments:
        if not line.startswith(("# alias:", "# manual:")):
            continue
        where = f"tools.tsv:{number}"
        alias, man = ALIAS_RE.match(line), MANUAL_RE.match(line)
        match = alias or man
        if not match:
            errors.append(f"[declaration] {where}: expected '# alias: ID NAME' or '# manual: ID SCOPES'")
            continue
        if match.group(1) not in tool_ids:
            errors.append(f"[declaration] {where}: unknown tool id {match.group(1)!r}")
            continue
        if alias:
            aliases.setdefault(alias.group(1), set()).add(alias.group(2))
            continue
        scopes = man.group(2).split(",")
        unknown = [s for s in scopes if s not in KNOWN_HOSTS and s not in PROFILES]
        if unknown:
            errors.append(f"[declaration] {where}: unknown scope {', '.join(unknown)}")
        manual.setdefault(man.group(1), set()).update(scopes)
    return aliases, manual


def check_tools(rows, errors):
    check_unique(rows, lambda r: r["id"], "tools.tsv", errors)
    for row in rows:
        where = f"tools.tsv:{row.line}"
        if not ID_RE.match(row["id"]):
            errors.append(f"[vocab] {where}: bad id {row['id']!r}")
        if row["id"] in RESERVED_IDS:
            errors.append(f"[reserved-id] {where}: {row['id']} is a structural doctor check")
        if row["tier"] not in TIERS:
            errors.append(f"[vocab] {where}: unknown tier {row['tier']!r}")
        problem = hosts_error(row["hosts"])
        if problem:
            errors.append(f"[vocab] {where}: {problem}")
        problem = probe_error(row["probe"], row["hosts"])
        if problem:
            errors.append(f"[probe] {where}: {problem}")
        if row["version_flag"] not in VERSION_FLAGS:
            errors.append(f"[vocab] {where}: unknown version_flag {row['version_flag']!r}")
        if row["floor"] != "-" and not FLOOR_RE.match(row["floor"]):
            errors.append(f"[floor] {where}: floor must be X.Y or X.Y.Z, not {row['floor']!r}")
        presence = ":" in row["probe"]
        if presence and (row["version_flag"] != "-" or row["floor"] != "-"):
            errors.append(f"[probe-version] {where}: {row['probe'].split(':')[0]} probes are presence-only")
        if row["floor"] != "-" and row["version_flag"] == "-":
            errors.append(f"[probe-version] {where}: a floor needs a version_flag")
        if row["doc"] not in STEP_IDS:
            errors.append(f"[doc] {where}: unknown step id {row['doc']!r}")


def check_clones(rows, tools, errors):
    check_unique(rows, lambda r: r["id"], "git-clones.tsv", errors)
    for row in rows:
        where = f"git-clones.tsv:{row.line}"
        if row["id"] not in tools:
            errors.append(f"[clone-id] {where}: {row['id']} is not a tools.tsv id")
        problem = path_error(row["dest"])
        if problem:
            errors.append(f"[clone-dest] {where}: {problem}")
        if not GITHUB_RE.match(row["url"]):
            errors.append(f"[clone-url] {where}: url must be https://github.com/OWNER/REPO.git")
        if row["id"] == "oh-my-zsh":
            if row["ref"] != "master":
                errors.append(f"[clone-ref] {where}: oh-my-zsh must track master (self-updating)")
        elif not COMMIT_RE.match(row["ref"]):
            errors.append(f"[clone-ref] {where}: ref must be a 40-hex commit")
        problem = hosts_error(row["hosts"])
        if problem:
            errors.append(f"[vocab] {where}: {problem}")
        elif host_matches(row["hosts"], "win"):
            errors.append(f"[clone-hosts] {where}: clones are Unix-only (use unix or a list)")
        tool = tools.get(row["id"])
        if tool and ":" in tool["probe"]:
            target = tool["probe"].partition(":")[2]
            if not target.startswith(row["dest"] + "/"):
                errors.append(f"[clone-probe] {where}: tools.tsv probe {target!r} is not inside {row['dest']}")
    missing = sorted(set(REQUIRED_CLONES) - {row["id"] for row in rows})
    if missing:
        errors.append(f"[clone-set] git-clones.tsv: missing {', '.join(missing)}")


def check_installers(rows, tools, errors):
    check_unique(rows, lambda r: (r["id"], r["arch"]), "installers.tsv", errors)
    for row in rows:
        where = f"installers.tsv:{row.line}"
        if row["id"] not in tools:
            errors.append(f"[installer-id] {where}: {row['id']} is not a tools.tsv id")
        for column, vocabulary in (("kind", KINDS), ("arch", ARCHES), ("tier", TIERS), ("human", HUMANS)):
            if row[column] not in vocabulary:
                errors.append(f"[vocab] {where}: unknown {column} {row[column]!r}")
        problem = hosts_error(row["hosts"])
        if problem:
            errors.append(f"[vocab] {where}: {problem}")
        if not row["url"].startswith("https://") or " " in row["url"]:
            errors.append(f"[installer-url] {where}: url must be https:// without spaces")
        if row["human"] == "inspect":
            if row["sha256"] != "-" and not SHA256_RE.match(row["sha256"]):
                errors.append(f"[sha256] {where}: sha256 must be - or 64 lowercase hex")
        else:
            if not SHA256_RE.match(row["sha256"]):
                errors.append(f"[sha256] {where}: sha256 must be 64 lowercase hex (- only for inspect)")
            if not PINNED_URL_RE.search(row["url"]):
                errors.append(f"[installer-pin] {where}: url must name a commit or version")
        if row["kind"] == "script":
            if row["dest"] != "-":
                errors.append(f"[installer-dest] {where}: scripts have dest -")
        else:
            problem = "dest - is only for scripts" if row["dest"] == "-" else path_error(row["dest"])
            if problem:
                errors.append(f"[installer-dest] {where}: {problem}")
    present = {(row["id"], row["arch"]) for row in rows}
    missing = [f"{i}/{a}" for i, a in REQUIRED_INSTALLERS if (i, a) not in present]
    if missing:
        errors.append(f"[installer-set] installers.tsv: missing {', '.join(missing)}")


def read_brewfiles(config, errors):
    """Return [(name, os_guard)] across all tier Brewfiles."""
    entries, seen = [], {}
    for tier in BREW_TIERS:
        rel = f"brew/{tier}.Brewfile"
        text = read_text(config / rel, rel, errors)
        if text is None:
            continue
        for number, line in enumerate(text.splitlines(), 1):
            where = f"{rel}:{number}"
            if line == "" or line.startswith("#") or TAP_RE.match(line):
                continue
            match = BREW_RE.match(line)
            if not match:
                errors.append(f"[brewfile] {where}: not brew \"x\", cask \"x\" if OS.mac?, tap or comment")
                continue
            kind, name, guard = match.groups()
            if kind == "cask" and guard != "mac":
                errors.append(f"[brewfile] {where}: casks need the if OS.mac? guard")
            base = name.rsplit("/", 1)[-1]
            if base in ("nvm", "openssh") or base.startswith("openssh@"):
                errors.append(f"[brewfile-forbidden] {where}: {base} must never be bundled")
            if name in seen:
                errors.append(f"[brewfile] {where}: {name} repeats {seen[name]}")
            seen[name] = where
            entries.append((name, guard))
    return entries


def read_apt(config, errors):
    lists = {}
    for name in ("common",) + tuple(APT_HOST_REQUIRED):
        rel = f"apt/{name}.txt"
        text = read_text(config / rel, rel, errors)
        packages = []
        for number, line in enumerate((text or "").splitlines(), 1):
            if line == "" or line.startswith("#"):
                continue
            if not APT_RE.match(line):
                errors.append(f"[apt] {rel}:{number}: {line!r} is not a bare package name")
            elif line in packages:
                errors.append(f"[apt] {rel}:{number}: {line} repeats")
            else:
                packages.append(line)
        lists[name] = packages
    if set(lists["common"]) != set(APT_COMMON):
        extra = sorted(set(lists["common"]) - set(APT_COMMON))
        missing = sorted(set(APT_COMMON) - set(lists["common"]))
        errors.append(f"[apt-set] apt/common.txt: missing {missing}, unexpected {extra}")
    for host, required in APT_HOST_REQUIRED.items():
        missing = sorted(set(required) - set(lists[host]))
        if missing:
            errors.append(f"[apt-set] apt/{host}.txt: missing {', '.join(missing)}")
        overlap = sorted(set(lists[host]) & set(lists["common"]))
        if overlap:
            errors.append(f"[apt] apt/{host}.txt: already in common.txt: {', '.join(overlap)}")
    return lists


def read_login_env(config, errors):
    """Parse the restricted YAML of hpc-login-env.yml into (name, channels, deps)."""
    rel = "hpc-login-env.yml"
    text = read_text(config / rel, rel, errors) or ""
    name, channels, deps, section = None, [], [], None
    for number, raw in enumerate(text.splitlines(), 1):
        where = f"{rel}:{number}"
        line = raw.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        if not raw[0].isspace():
            key, sep, value = line.partition(":")
            value = value.strip()
            section = None
            if not sep or key not in ("name", "channels", "dependencies"):
                errors.append(f"[yml] {where}: only name, channels and dependencies are allowed")
            elif key == "name":
                name = value
            elif value.startswith("[") and value.endswith("]"):
                items = [v.strip() for v in value[1:-1].split(",") if v.strip()]
                (channels if key == "channels" else deps).extend((number, i) for i in items)
            elif value:
                errors.append(f"[yml] {where}: {key} must be a list")
            else:
                section = key
            continue
        item = line.strip()
        if section is None or not item.startswith("- "):
            errors.append(f"[yml] {where}: expected a '- item' under channels or dependencies")
            continue
        (channels if section == "channels" else deps).append((number, item[2:].strip()))
    return name, [c for _, c in channels], deps


def check_login_env(config, tools, aliases, errors):
    name, channels, deps = read_login_env(config, errors)
    if name != "login":
        errors.append("[yml] hpc-login-env.yml: name must be login")
    if channels != ["conda-forge"]:
        errors.append("[yml] hpc-login-env.yml: channels must be exactly [conda-forge]")
    names = {}
    for number, dep in deps:
        where = f"hpc-login-env.yml:{number}"
        match = DEP_RE.match(dep)
        if not match:
            errors.append(f"[yml] {where}: bad dependency {dep!r}")
            continue
        package, spec = match.groups()
        if package in names:
            errors.append(f"[yml] {where}: {package} repeats")
        names[package] = spec
        if package in LOGIN_TRAPS:
            errors.append(f"[yml-trap] {where}: use {LOGIN_TRAPS[package]} instead of {package}")
        tool = next((t for t in tools.values() if package == t["id"] or package in aliases.get(t["id"], ())), None)
        if tool and tool["floor"] != "-" and spec != f">={tool['floor']}":
            errors.append(f"[yml-floor] {where}: {package} must be pinned >={tool['floor']} like tools.tsv")
    missing = sorted(set(LOGIN_REQUIRED) - set(names))
    if missing:
        errors.append(f"[yml-set] hpc-login-env.yml: missing {', '.join(missing)}")
    return set(names) | ({name} if name else set())


def read_winget(config, errors):
    rel = "winget.json"
    text = read_text(config / rel, rel, errors)
    if text is None:
        return set()
    try:
        data = json.loads(text)
    except json.JSONDecodeError as error:
        errors.append(f"[winget] {rel}: invalid JSON ({error.msg})")
        return set()
    if not isinstance(data, dict) or data.get("$schema") != WINGET_SCHEMA:
        errors.append(f"[winget] {rel}: $schema must be {WINGET_SCHEMA}")
        return set()
    if not isinstance(data.get("CreationDate"), str):
        errors.append(f"[winget] {rel}: CreationDate is required")
    sources = data.get("Sources")
    if not isinstance(sources, list) or not sources:
        errors.append(f"[winget] {rel}: Sources must be a non-empty list")
        return set()
    ids = []
    for index, source in enumerate(sources):
        details = source.get("SourceDetails") if isinstance(source, dict) else None
        keys = ("Name", "Identifier", "Argument", "Type")
        if not isinstance(details, dict) or not all(isinstance(details.get(k), str) for k in keys):
            errors.append(f"[winget] {rel}: Sources[{index}].SourceDetails needs {', '.join(keys)}")
        packages = source.get("Packages") if isinstance(source, dict) else None
        if not isinstance(packages, list) or not packages:
            errors.append(f"[winget] {rel}: Sources[{index}].Packages must be a non-empty list")
            continue
        for package in packages:
            identifier = package.get("PackageIdentifier") if isinstance(package, dict) else None
            if not isinstance(identifier, str) or not WINGET_ID_RE.match(identifier):
                errors.append(f"[winget] {rel}: bad PackageIdentifier {identifier!r}")
            elif identifier in ids:
                errors.append(f"[winget] {rel}: {identifier} repeats")
            else:
                ids.append(identifier)
    if not any(isinstance(s, dict) and isinstance(s.get("SourceDetails"), dict)
               and s["SourceDetails"].get("Name") == "winget" for s in sources):
        errors.append(f"[winget] {rel}: no source named winget")
    missing = sorted(set(WINGET_REQUIRED) - set(ids))
    if missing:
        errors.append(f"[winget-set] {rel}: missing {', '.join(missing)}")
    return set(ids)


def check_coverage(tools, aliases, manual, sources, errors):
    for row in tools.values():
        if row["tier"] not in COVERED_TIERS or hosts_error(row["hosts"]):
            continue
        names = {row["id"]} | aliases.get(row["id"], set())
        for host in expand_hosts(row["hosts"]):
            scopes = manual.get(row["id"], set())
            if names & sources[host] or host in scopes or HOST_PROFILE[host] in scopes:
                continue
            errors.append(f"[coverage] tools.tsv:{row.line}: no manifest installs {row['id']} on {host};"
                          " add it to one, or declare '# alias:' or '# manual:'")


def host_sources(host, brew, apt, login, winget, clones, installers):
    profile = HOST_PROFILE[host]
    names = {r["id"] for r in clones + installers if not hosts_error(r["hosts"]) and host_matches(r["hosts"], host)}
    if profile == "macos":
        names |= {name for name, guard in brew if guard != "linux"}
    elif profile == "debian":
        names |= {name for name, guard in brew if guard != "mac"}
        names |= set(apt.get("common", ())) | set(apt.get(host, ()))
    elif profile == "hpc":
        names |= login
    else:
        names |= winget
    return names


def check_file_text(config, errors):
    for path in sorted(p for p in config.rglob("*") if p.is_file()):
        rel = path.relative_to(config).as_posix()
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            errors.append(f"[tsv-format] {rel}: not UTF-8")
            continue
        for number, line in enumerate(text.splitlines(), 1):
            if HOME_RE.search(line):
                errors.append(f"[home-literal] {rel}:{number}: machine-specific home path")
        if path.suffix != ".json" and not PINNED_RE.search(text):
            errors.append(f"[pinned-header] {rel}: needs a '# pinned YYYY-MM-DD' comment")


def check_docs(repo, tools, errors):
    text = read_text(repo / "docs/bootstrap.md", "docs/bootstrap.md", errors) or ""
    found = [m.group(1) for m in map(HEADING_RE.match, text.splitlines()) if m]
    for step in STEP_IDS:
        if found.count(step) != 1:
            errors.append(f"[docs-headings] docs/bootstrap.md: {found.count(step)} '### {step}:' headings, expected 1")
    for step in sorted(set(found) - set(STEP_IDS)):
        errors.append(f"[docs-headings] docs/bootstrap.md: '### {step}:' is not a contract step id")
    text = read_text(repo / "docs/dependencies.md", "docs/dependencies.md", errors) or ""
    cells = set()
    for line in text.splitlines():
        if line.startswith("|"):
            cells.update(cell.strip().strip("`") for cell in line.strip("|").split("|"))
    for row in tools.values():
        if row["id"] not in cells:
            errors.append(f"[docs-deps] docs/dependencies.md: no table cell for tools id {row['id']}")


def split_skill(path, rel, errors):
    text = read_text(path, rel, errors)
    if text is None:
        return None, None
    if not text.startswith("---\n") or "\n---\n" not in text[3:]:
        errors.append(f"[skill] {rel}: missing --- frontmatter")
        return None, None
    end = text.index("\n---\n", 3)
    keys = {}
    for line in text[4:end].splitlines():
        if not line.strip() or line[0].isspace() or line.lstrip().startswith("#"):
            continue
        key, sep, value = line.partition(":")
        if not sep:
            errors.append(f"[skill] {rel}: bad frontmatter line {line!r}")
            continue
        keys[key.strip()] = value.strip()
    return keys, text[end + 5:]


def check_skills(repo, errors):
    claude, claude_body = split_skill(repo / SKILL_CLAUDE, SKILL_CLAUDE.as_posix(), errors)
    codex, codex_body = split_skill(repo / SKILL_CODEX, SKILL_CODEX.as_posix(), errors)
    for rel, keys, allowed in ((SKILL_CLAUDE, claude, CLAUDE_KEYS), (SKILL_CODEX, codex, CODEX_KEYS)):
        if keys is None:
            continue
        if keys.get("name") != rel.parent.name or not SKILL_NAME_RE.match(keys.get("name", "")):
            errors.append(f"[skill] {rel.as_posix()}: name must equal the directory name {rel.parent.name}")
        if not 0 < len(keys.get("description", "")) <= 1024:
            errors.append(f"[skill] {rel.as_posix()}: description must be 1-1024 characters")
        if len(keys.get("compatibility", "")) > 500:
            errors.append(f"[skill] {rel.as_posix()}: compatibility is over 500 characters")
        extra = sorted(set(keys) - allowed)
        if extra:
            errors.append(f"[skill] {rel.as_posix()}: frontmatter keys not allowed: {', '.join(extra)}")
    if claude is not None and claude.get("disable-model-invocation") != "true":
        errors.append(f"[skill] {SKILL_CLAUDE.as_posix()}: needs disable-model-invocation: true")
    if claude_body is not None and codex_body is not None and claude_body != codex_body:
        errors.append("[skill] SKILL.md bodies differ between .claude/skills and .agents/skills")


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
    brew = read_brewfiles(config, errors)
    apt = read_apt(config, errors)
    login = check_login_env(config, tools, aliases, errors)
    winget = read_winget(config, errors)
    sources = {host: host_sources(host, brew, apt, login, winget, clone_rows, installer_rows)
               for host in KNOWN_HOSTS}
    check_coverage(tools, aliases, manual, sources, errors)
    check_file_text(config, errors)
    check_docs(repo, tools, errors)
    check_skills(repo, errors)
    return errors


class RepositoryManifestTests(unittest.TestCase):
    def test_repository_manifests_docs_and_skills_are_valid(self):
        self.assertEqual(validate(ROOT / "config/bootstrap", ROOT), [])


class RejectionTests(unittest.TestCase):
    """Each case breaks a copy of the real files and expects its rule to fire."""

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
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

    def append(self, rel, text):
        with self.path(rel).open("a", encoding="utf-8") as handle:
            handle.write(text)

    def row(self, rel, row_id):
        for line in self.path(rel).read_text(encoding="utf-8").splitlines():
            if line.startswith(row_id + "\t"):
                return line
        self.fail(f"no {row_id} row in {rel}")

    def set_cell(self, rel, row_id, column, value, columns):
        old = self.row(rel, row_id)
        cells = old.split("\t")
        cells[columns.index(column)] = value
        self.replace(rel, old, "\t".join(cells))

    def assertRule(self, rule, case):
        errors = self.errors()
        self.assertTrue(any(e.startswith(f"[{rule}]") for e in errors), f"{case}: {rule} not in {errors}")

    def check_each(self, rule, cases):
        for name, mutate in cases:
            with self.subTest(name):
                self.setUp()
                mutate()
                self.assertRule(rule, name)

    def tools(self, row_id, column, value):
        return lambda: self.set_cell("tools.tsv", row_id, column, value, TOOLS_COLUMNS)

    def clones(self, row_id, column, value):
        return lambda: self.set_cell("git-clones.tsv", row_id, column, value, CLONES_COLUMNS)

    def installers(self, row_id, column, value):
        return lambda: self.set_cell("installers.tsv", row_id, column, value, INSTALLERS_COLUMNS)

    def test_tsv_structure(self):
        fzf = "fzf\tcore\tall\tfzf\t--version\t0.58.0\tbroken\tS2-brew-bundle"
        self.check_each("tsv-format", [
            ("header", lambda: self.replace("tools.tsv", "id\ttier\thosts", "id\ttiers\thosts")),
            ("trailing tab", lambda: self.replace("tools.tsv", self.row("tools.tsv", "fzf"), fzf + "\t")),
            ("empty cell", lambda: self.replace("tools.tsv", self.row("tools.tsv", "fzf"), fzf.replace("0.58.0", ""))),
            ("blank line", lambda: self.append("tools.tsv", "\n\n")),
        ])

    def test_unique_ids(self):
        self.check_each("dup-id", [
            ("tools", lambda: self.append("tools.tsv", self.row("tools.tsv", "fzf") + "\n")),
            ("clones", lambda: self.append("git-clones.tsv", self.row("git-clones.tsv", "fzf-tab") + "\n")),
            ("installer arch", lambda: self.append("installers.tsv", self.row("installers.tsv", "nvm") + "\n")),
        ])

    def test_vocabularies(self):
        self.check_each("vocab", [
            ("tier", self.tools("fzf", "tier", "essential")),
            ("host", self.tools("fzf", "hosts", "mac,ubuntu")),
            ("duplicate host", self.tools("kitty", "hosts", "mac,mac")),
            ("version flag", self.tools("fzf", "version_flag", "--ver")),
            ("id", self.tools("fzf", "id", "Fzf")),
            ("installer kind", self.installers("nvm", "kind", "pipe")),
            ("installer arch", self.installers("nvm", "arch", "arm64")),
            ("installer human", self.installers("nvm", "human", "maybe")),
        ])
        self.check_each("reserved-id", [("locale", self.tools("fzf", "id", "locale"))])

    def test_probes_versions_and_floors(self):
        self.check_each("probe", [
            ("unknown token", self.tools("oh-my-zsh", "probe", "file:$FOO/x")),
            ("second token", self.tools("oh-my-zsh", "probe", "file:$HOME/$HOME/x")),
            ("tilde", self.tools("oh-my-zsh", "probe", "file:~/.oh-my-zsh/oh-my-zsh.sh")),
            ("dotdot", self.tools("oh-my-zsh", "probe", "file:$HOME/../x")),
            ("relative", self.tools("oh-my-zsh", "probe", "file:.oh-my-zsh")),
            ("kind", self.tools("oh-my-zsh", "probe", "url:https")),
            ("command", self.tools("fzf", "probe", "fzf --bin")),
            ("psmodule host", self.tools("psfzf", "hosts", "all")),
            ("env", self.tools("lmod", "probe", "env:lmod-dir")),
        ])
        self.check_each("floor", [("floor", self.tools("fzf", "floor", "0.58.x"))])
        self.check_each("probe-version", [
            ("presence with flag", self.tools("oh-my-zsh", "version_flag", "--version")),
            ("floor without flag", self.tools("fzf", "version_flag", "-")),
        ])

    def test_doc_ids_and_headings(self):
        self.check_each("doc", [("unknown step", self.tools("fzf", "doc", "S3-bat-cache"))])
        self.check_each("docs-headings", [
            ("missing", lambda: self.replace("docs/bootstrap.md", "### S3-clones:", "### S3 clones:")),
            ("duplicate", lambda: self.append("docs/bootstrap.md", "\n### S3-clones: again\n")),
            ("unknown", lambda: self.append("docs/bootstrap.md", "\n### S3-bat-cache: stale\n")),
        ])
        self.check_each("docs-deps", [
            ("missing id", lambda: self.replace("docs/dependencies.md", "| `fzf-tab` |", "| fzf tab |")),
        ])

    def test_clones(self):
        self.check_each("clone-id", [("unknown id", self.clones("fzf-tab", "id", "fzf-tabs"))])
        self.check_each("clone-ref", [
            ("branch", self.clones("fzf-tab", "ref", "master")),
            ("short sha", self.clones("fzf-tab", "ref", "d7e0234")),
            ("omz pinned", self.clones("oh-my-zsh", "ref", "42a4ccb1b14dbeffe81259105a5243b4f4cb618e")),
        ])
        self.check_each("clone-url", [("not github .git", self.clones("fzf-tab", "url", "https://gitlab.com/a/b"))])
        self.check_each("clone-hosts", [("windows", self.clones("fzf-tab", "hosts", "all"))])
        self.check_each("clone-dest", [("token", self.clones("fzf-tab", "dest", "$ZSH/custom/plugins/fzf-tab"))])
        self.check_each("clone-probe", [("moved", self.clones("fzf-tab", "dest", "$ZSH_CUSTOM/plugins/tab"))])
        self.check_each("clone-set", [("missing", lambda: self.replace(
            "git-clones.tsv", self.row("git-clones.tsv", "zsh-completions") + "\n", ""))])

    def test_installers(self):
        self.check_each("sha256", [
            ("dash without inspect", self.installers("nvm", "sha256", "-")),
            ("uppercase", self.installers("nvm", "sha256", "48A0EEE9A60E07422DCE0EB5774754C83889570CA1EE2566C516ACBE8AF03A9E")),
            ("short", self.installers("nvm", "sha256", "48a0eee9")),
        ])
        self.check_each("installer-pin", [
            ("branch url", self.installers("nvm", "url", "https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh")),
        ])
        self.check_each("installer-url", [("http", self.installers("nvm", "url", "http://example.com/v1.0/x.sh"))])
        self.check_each("installer-dest", [
            ("script dest", self.installers("nvm", "dest", "$HOME/nvm.sh")),
            ("archive without dest", self.installers("nerd-font", "dest", "-")),
            ("bad token", self.installers("nerd-font", "dest", "$FONTS/x")),
        ])
        self.check_each("installer-id", [("unknown", self.installers("nvm", "id", "nvm-sh"))])
        self.check_each("installer-set", [("missing", lambda: self.replace(
            "installers.tsv", self.row("installers.tsv", "claude") + "\n", ""))])

    def test_forbidden_characters_and_home_literals(self):
        self.check_each("cell-chars", [
            ("semicolon", self.tools("fzf", "absent", "fails; badly")),
            ("pipe", self.tools("fzf", "absent", "fails | badly")),
            ("ampersand", self.tools("fzf", "absent", "fails & badly")),
            ("dollar paren", self.tools("fzf", "probe", "file:$HOME/$(id)")),
            ("backtick", self.tools("fzf", "absent", "fails `x`")),
            ("dollar in absent", self.tools("fzf", "absent", "fails at $HOME")),
        ])
        self.check_each("home-literal", [
            ("linux home", lambda: self.append("tools.tsv", "# see /home/alice/x\n")),
            ("mac home", lambda: self.append("apt/common.txt", "# /Users/alice\n")),
            ("cluster home", lambda: self.append("hpc-login-env.yml", "# /users/alice\n")),
            ("windows home", lambda: self.append("brew/core.Brewfile", "# C:\\Users\\alice\n")),
        ])
        self.check_each("pinned-header", [("missing", lambda: self.replace("apt/wsl-ubuntu.txt", "# pinned", "# fixed"))])

    def test_brewfiles_and_apt_lists(self):
        self.check_each("brewfile-forbidden", [
            ("openssh", lambda: self.append("brew/core.Brewfile", 'brew "openssh"\n')),
            ("nvm", lambda: self.append("brew/ai.Brewfile", 'brew "nvm"\n')),
        ])
        self.check_each("brewfile", [
            ("ruby", lambda: self.append("brew/cli.Brewfile", 'system "curl x | sh"\n')),
            ("options", lambda: self.append("brew/cli.Brewfile", 'brew "jq", args: ["HEAD"]\n')),
            ("unguarded cask", lambda: self.append("brew/desktop.Brewfile", 'cask "iterm2"\n')),
            ("repeat", lambda: self.append("brew/contributor.Brewfile", 'brew "fzf"\n')),
        ])
        self.check_each("apt", [
            ("version", lambda: self.append("apt/lab-ubuntu.txt", "zsh=5.9\n")),
            ("trailing comment", lambda: self.append("apt/wsl-ubuntu.txt", "jq # json\n")),
            ("overlap", lambda: self.append("apt/lab-ubuntu.txt", "tmux\n")),
        ])
        self.check_each("apt-set", [
            ("common extra", lambda: self.append("apt/common.txt", "jq\n")),
            ("host missing", lambda: self.replace("apt/lab-ubuntu.txt", "xclip\n", "")),
        ])

    def test_winget_and_login_env(self):
        self.check_each("winget", [
            ("json", lambda: self.append("winget.json", "}")),
            ("schema", lambda: self.replace("winget.json", "schema.2.0", "schema.1.0")),
            ("source details", lambda: self.replace("winget.json", '"SourceDetails"', '"Details"')),
            ("package id", lambda: self.replace("winget.json", '"PackageIdentifier": "jqlang.jq"', '"Id": "jq"')),
        ])
        self.check_each("winget-set", [("dropped", lambda: self.replace(
            "winget.json", '"PackageIdentifier": "jqlang.jq"', '"PackageIdentifier": "stedolan.jq"'))])
        self.check_each("yml-set", [("missing", lambda: self.replace("hpc-login-env.yml", "  - tealdeer\n", ""))])
        self.check_each("yml-trap", [("neovim", lambda: self.replace("hpc-login-env.yml", "  - nvim\n", "  - neovim\n"))])
        self.check_each("yml-floor", [("floor", lambda: self.replace("hpc-login-env.yml", "fzf>=0.58.0", "fzf>=0.44"))])
        self.check_each("yml", [
            ("channel", lambda: self.replace("hpc-login-env.yml", "  - conda-forge\n", "  - defaults\n")),
            ("key", lambda: self.append("hpc-login-env.yml", "prefix: /opt/login\n")),
        ])

    def test_skills(self):
        self.check_each("skill", [
            ("body", lambda: self.append(SKILL_CODEX, "Extra line.\n")),
            ("name", lambda: self.replace(SKILL_CLAUDE, "name: dotfiles-bootstrap", "name: bootstrap")),
            ("codex key", lambda: self.replace(SKILL_CODEX, "metadata:", "disable-model-invocation: true\nmetadata:")),
            ("claude flag", lambda: self.replace(SKILL_CLAUDE, "disable-model-invocation: true\n", "")),
            ("frontmatter", lambda: self.replace(SKILL_CODEX, "---\nname", "name")),
        ])

    def test_coverage_and_declarations(self):
        self.check_each("coverage", [
            ("alias removed", lambda: self.replace("tools.tsv", "# alias: fzf junegunn.fzf\n", "")),
            ("manual removed", lambda: self.replace("tools.tsv", "# manual: claude hpc\n", "")),
            ("brew entry removed", lambda: self.replace("brew/cli.Brewfile", 'brew "jq"\n', "")),
        ])
        self.check_each("declaration", [
            ("malformed", lambda: self.append("tools.tsv", "# alias: fzf\n")),
            ("unknown id", lambda: self.append("tools.tsv", "# alias: fzz junegunn.fzf\n")),
            ("unknown scope", lambda: self.append("tools.tsv", "# manual: claude cluster\n")),
        ])

    def test_missing_manifest(self):
        self.check_each("missing-file", [("winget", lambda: (self.config / "winget.json").unlink())])


if __name__ == "__main__":
    unittest.main()
