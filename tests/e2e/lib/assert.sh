# shellcheck shell=bash
# shellcheck disable=SC2034 # the guard state (E2E_VENV_VIOLATIONS, E2E_LOGIN_SHELL_START, E2E_STOW_START) is read by steps.sh and inside.sh
# The checks of tests/e2e/inside.sh that watch the home and the clone: the
# no-write snapshots (an empty TMPDIR, HOME by find -newer and entry count),
# the clean-clone rule, the per-step guards (rc-file digests, the AI-sync
# runtime in the clone), the login-shell run and the acceptance audits
# (wrappers.log phases, sudo.log timestamps against the timeline, links
# under HOME that lead into the clone, a stow on the login PATH). Sourced
# after common.sh; same
# portability rules (no find -printf, no stat, no readlink -f, no date -d
# except inside the sudo.log audit, which Linux alone needs).

# Guard state: the before-images e2e_step_begin takes, the violations the
# audits report at the end, and the notes e2e_step_end appends after a row.
# E2E_SYNC_VENV is the AI-sync runtime directory the legacy route made in
# the clone; the native flow never creates it.
E2E_RC_FILES='.bashrc .profile .bash_profile .zshrc .zshenv .zprofile'
E2E_RC_BEFORE='' E2E_RC_VIOLATIONS=''
E2E_SYNC_VENV=.venv-sync
E2E_VENV_VIOLATIONS=''
E2E_PENDING_NOTES=''
E2E_LOGIN_SHELL_START=''
# The stow executables the machine had before the flow (e2e_stow_start).
E2E_STOW_START=''
E2E_LOGIN_DETAIL=''
E2E_LOGIN_ENV=()
E2E_PRUNE=()
E2E_NW_TMP='' E2E_NW_REF='' E2E_NW_MARKER='' E2E_NW_COUNT=0

# --- the clone ---------------------------------------------------------------

# e2e_clone_dirty: git status --porcelain of the clone, with every untracked
# file on its own line; a git failure is one line too, so it reads as dirty.
# Returns 1 while there is no clone.
e2e_clone_dirty() {
    [ -e "$E2E_CLONE/.git" ] || return 1
    git -C "$E2E_CLONE" status --porcelain --untracked-files=all 2>/dev/null </dev/null ||
        printf '%s\n' '(git status failed)'
}

# --- per-step guards ---------------------------------------------------------

# e2e_rc_sums: "<name>=<sha256>" for each rc file of E2E_RC_FILES that
# exists in HOME (a link is read through; a dangling one counts as missing).
e2e_rc_sums() {
    local name sum out=''
    for name in $E2E_RC_FILES; do
        [ -f "$HOME/$name" ] || continue
        sum=$(e2e_sha256 "$HOME/$name") || sum=unreadable
        out="$out${out:+ }$name=$sum"
    done
    printf '%s\n' "$out"
}

# e2e_rc_pick SUMS NAME: NAME's digest in a e2e_rc_sums list, or missing.
e2e_rc_pick() {
    local rest=" $1 "
    case $rest in
        *" $2="*)
            rest=${rest#*" $2="}
            printf '%s\n' "${rest%% *}"
            ;;
        *) printf 'missing\n' ;;
    esac
}

# e2e_rc_diff BEFORE AFTER: the rc files whose digest differs.
e2e_rc_diff() {
    local name out=''
    for name in $E2E_RC_FILES; do
        [ "$(e2e_rc_pick "$1" "$name")" = "$(e2e_rc_pick "$2" "$name")" ] || out="$out${out:+ }$name"
    done
    printf '%s\n' "$out"
}

e2e_guard_before() {
    E2E_RC_BEFORE=$(e2e_rc_sums)
}

# e2e_guard_after STEP PHASE: compare with the before-images. The rc files
# may change during a human:* phase only (recorded as a note: the
# native-handover step, in human:H7-native, replaces the /etc/skel files
# with the deployed ones after keeping a copy of each). The first step after
# which the clone holds E2E_SYNC_VENV (a directory, a file or a link) is
# recorded once for the audit.
e2e_guard_after() {
    local step=$1 phase=$2 after changed
    after=$(e2e_rc_sums)
    if [ "$after" != "$E2E_RC_BEFORE" ]; then
        changed=$(e2e_rc_diff "$E2E_RC_BEFORE" "$after")
        case $phase in
            human:*) E2E_PENDING_NOTES="${E2E_PENDING_NOTES}rc-files${E2E_TAB}changed during $phase: $changed$E2E_NL" ;;
            *) E2E_RC_VIOLATIONS="$E2E_RC_VIOLATIONS${E2E_RC_VIOLATIONS:+; }$step ($phase): $changed" ;;
        esac
    fi
    if [ -z "$E2E_VENV_VIOLATIONS" ] && [ -n "${E2E_CLONE:-}" ] &&
        { [ -e "$E2E_CLONE/$E2E_SYNC_VENV" ] || [ -L "$E2E_CLONE/$E2E_SYNC_VENV" ]; }; then
        E2E_VENV_VIOLATIONS="$step ($phase)"
    fi
}

# --- no-write snapshots ------------------------------------------------------

# e2e_prune_args: the find arguments that leave out what a snapshot must not
# count: the clone's .git (git status refreshes its index), E2E_OUT and
# E2E_SRC when they are under HOME, and E2E_SNAPSHOT_PRUNE (the mac runner's
# $HOME/work and $HOME/Library, its Actions agent under $HOME/runners or
# $HOME/actions-runner, whose _diag logs are appended throughout the job, and
# $HOME/hostedtoolcache).
# env.txt records the expanded list, so a reader of the artifact sees what
# the no-write checks did not watch.
e2e_prune_args() {
    local path
    E2E_PRUNE=('(' -path "$E2E_CLONE/.git" -o -path "$E2E_OUT" -o -path "$E2E_SRC")
    for path in $(e2e_expand "${E2E_SNAPSHOT_PRUNE:-}"); do
        E2E_PRUNE=("${E2E_PRUNE[@]}" -o -path "$path")
    done
    E2E_PRUNE=("${E2E_PRUNE[@]}" ')' -prune -o)
}

# e2e_home_count: entries under HOME outside the prune list.
e2e_home_count() {
    find "$HOME" "${E2E_PRUNE[@]}" -print 2>/dev/null | wc -l | tr -d ' '
}

# e2e_nowrite_begin NAME: the before-image of a step that must write
# nothing: TMPDIR = a fresh empty E2E_OUT/tmp/NAME with an old mtime (a file
# created or removed there moves it, however briefly it existed), a marker
# file outside HOME for find -newer, and the HOME entry count. Sleeps one
# second so a filesystem with second mtimes still tells the marker from a
# write that follows it.
e2e_nowrite_begin() {
    E2E_NW_TMP=$E2E_OUT/tmp/$1
    E2E_NW_REF=$E2E_OUT/tmp/$1.ref
    E2E_NW_MARKER=$E2E_OUT/snapshots/$1.marker
    rm -rf "$E2E_NW_TMP"
    mkdir -p "$E2E_NW_TMP"
    : >"$E2E_NW_REF"
    touch -t 200001010000 "$E2E_NW_TMP" "$E2E_NW_REF"
    e2e_prune_args
    : >"$E2E_NW_MARKER"
    sleep 1
    E2E_NW_COUNT=$(e2e_home_count)
}

# e2e_nowrite_end NAME: the violations, or nothing: a TMPDIR that is not
# empty or whose mtime moved, HOME files newer than the marker (kept in
# snapshots/NAME.newer) or a changed entry count.
e2e_nowrite_end() {
    local out='' left newer count
    left=$(ls -A "$E2E_NW_TMP" 2>/dev/null)
    [ -z "$left" ] || out="TMPDIR not empty: $(e2e_one_line "$left" 200)"
    if [ -n "$(find "$E2E_NW_TMP" -maxdepth 0 -newer "$E2E_NW_REF" 2>/dev/null)" ]; then
        out="$out${out:+; }TMPDIR mtime changed"
    fi
    newer=$(find "$HOME" "${E2E_PRUNE[@]}" -newer "$E2E_NW_MARKER" -print 2>/dev/null)
    printf '%s' "${newer:+$newer$E2E_NL}" >"$E2E_OUT/snapshots/$1.newer"
    [ -z "$newer" ] || out="$out${out:+; }HOME written: $(e2e_one_line "$newer" 300)"
    count=$(e2e_home_count)
    [ "$count" = "$E2E_NW_COUNT" ] || out="$out${out:+; }HOME entries $E2E_NW_COUNT -> $count"
    printf '%s\n' "$out"
}

# --- the login shell ---------------------------------------------------------

# e2e_login_env: the environment a fresh terminal or ssh session starts the
# login shell with: nothing inherited but HOME, the user, TERM and the system
# PATH (plus the wrappers' bin on the mac runner), the update hooks and
# gitstatus's installer off, and the harness variables the wrappers read, so
# a sudo from an rc file is logged under this phase and fails the audit.
e2e_login_env() {
    E2E_LOGIN_ENV=(env -i "HOME=$HOME" "USER=$E2E_RUN_USER" "LOGNAME=$E2E_RUN_USER" TERM=xterm-256color
        "PATH=$E2E_SYS_PATH" DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0 GITSTATUS_AUTO_INSTALL=0
        "E2E_OUT=$E2E_OUT" "E2E_PHASE=${E2E_PHASE:--}")
}

# e2e_login_zsh: E2E_LOGIN_ZSH expanded (zsh on PATH, or the hpc login env's).
e2e_login_zsh() {
    e2e_expand "${E2E_LOGIN_ZSH:-zsh}"
}

# e2e_login_run OUT ERR COMMAND [LIMIT]: bash -l, then the host's zsh as an
# interactive login shell running COMMAND, from that environment, under
# LIMIT seconds (default E2E_TIMEOUT_CHECK).
e2e_login_run() {
    local cmd
    cmd="exec $(e2e_quote "$(e2e_login_zsh)") -il -c $(e2e_quote "$3")"
    e2e_login_env
    e2e_run "$1" "$2" "${4:-$E2E_TIMEOUT_CHECK}" "$HOME" "${E2E_LOGIN_ENV[@]}" bash -lc "$cmd"
}

# e2e_login_noise ERR: the stderr of the login shell minus what only the
# missing terminal causes: the .zshrc's `stty -ixon` ("stty: ... ioctl" /
# "stty: stdin isn't a terminal"), and fzf's `--zsh` integration restoring
# the options it saved with `eval 'options=(... zle on ...)'`, which prints
# "(eval):1: can't change option: zle" since zle cannot be turned on without
# a terminal. Both are silent in a real terminal; anything else stays.
e2e_login_noise() {
    grep -Ev "^stty: |^\(eval\):1: can't change option: zle\$" "$1" 2>/dev/null || true
}

# e2e_login_text OUT: the stdout of the login shell minus terminal control
# sequences (CSI escapes and carriage returns): Fedora's stock /etc/zlogout
# runs `clear` when a login shell exits, which is screen control, not a
# message. Any text that remains is one.
e2e_login_text() {
    local esc
    esc=$(printf '\033')
    sed "s/${esc}\\[[0-9;?]*[A-Za-z]//g" "$1" 2>/dev/null | tr -d '\r' | grep . || true
}

# e2e_login_shell_check OUT ERR: the login shell must exit 0 and print
# nothing: stdout empty once e2e_login_text has dropped terminal control,
# stderr empty once the no-terminal lines of e2e_login_noise are dropped.
# E2E_LOGIN_DETAIL gets what it printed, with the known complaints
# (oh-my-zsh, the dotfiles hooks, not found, permission denied, [error])
# quoted first.
e2e_login_shell_check() {
    local out=$1 err=$2 rc=0 text noise findings
    e2e_login_run "$out" "$err" exit || rc=$?
    text=$(e2e_login_text "$out")
    noise=$(e2e_login_noise "$err")
    findings=$(grep -E '^\[(oh-my-zsh|dotfiles)\]|not found|[Pp]ermission denied|\[error\]' \
        "$out" "$err" 2>/dev/null) || true
    E2E_LOGIN_DETAIL="exit $rc"
    [ -z "$findings" ] || E2E_LOGIN_DETAIL="$E2E_LOGIN_DETAIL; findings: $(e2e_one_line "$findings" 300)"
    [ -z "$text" ] || E2E_LOGIN_DETAIL="$E2E_LOGIN_DETAIL; stdout: $(e2e_one_line "$text" 200)"
    [ -z "$noise" ] || E2E_LOGIN_DETAIL="$E2E_LOGIN_DETAIL; stderr: $(e2e_one_line "$noise" 200)"
    [ "$rc" = 0 ] && [ -z "$text" ] && [ -z "$noise" ]
}

# e2e_login_shell_of: the user's login shell from the account database
# (getent on Linux, dscl on macOS), else SHELL.
e2e_login_shell_of() {
    local entry
    if command -v getent >/dev/null 2>&1 &&
        entry=$(getent passwd "$E2E_RUN_USER" 2>/dev/null </dev/null) && [ -n "$entry" ]; then
        printf '%s\n' "${entry##*:}"
    elif command -v dscl >/dev/null 2>&1 &&
        entry=$(dscl . -read "/Users/$E2E_RUN_USER" UserShell 2>/dev/null </dev/null) && [ -n "$entry" ]; then
        printf '%s\n' "${entry##* }"
    else
        printf '%s\n' "${SHELL:-unknown}"
    fi
}

# --- audits ------------------------------------------------------------------

# e2e_audit_wrappers LOG: the wrappers.log lines ("<epoch>\t<phase>\t<tool>
# \t<ppid>\t<parent>\t<argv>") whose phase is neither human:* nor
# negative:*: a sudo or chsh that ran where only the harness's own
# read-only steps should have. No call is exempt, a version probe
# included. 0 when there are none.
e2e_audit_wrappers() {
    local bad
    bad=$(awk -F '\t' '$2 !~ /^(human|negative):/' "$1" 2>/dev/null)
    printf '%s\n' "$bad"
    [ -z "$bad" ]
}

# e2e_audit_clone_links: every link under HOME, outside the clone, E2E_OUT,
# E2E_SRC and E2E_SNAPSHOT_PRUNE, that leads into the clone (a Stow link, or
# anything else a step made point at the checkout), one per line. A link
# whose text names the clone's basename is resolved without following it
# further than cd -P does: its target (absolute, or the link's directory
# plus the text) when that is a directory, else the target's directory, and
# it counts when that is the physical clone or lies under it, a dangling
# link into the clone included. 0 when there are none. BSD-safe: no
# readlink -f, no find -printf.
e2e_audit_clone_links() {
    local phys base path found
    local prune=()
    [ -d "${E2E_CLONE:-}" ] || return 0
    phys=$(cd -P -- "$E2E_CLONE" 2>/dev/null && pwd -P) || return 0
    base=${E2E_CLONE##*/}
    prune=('(' -path "$E2E_CLONE" -o -path "${E2E_OUT:-}" -o -path "${E2E_SRC:-}")
    for path in $(e2e_expand "${E2E_SNAPSHOT_PRUNE:-}"); do
        prune=("${prune[@]}" -o -path "$path")
    done
    prune=("${prune[@]}" ')' -prune -o)
    found=$(
        find "$HOME" "${prune[@]}" -type l -print 2>/dev/null | while IFS= read -r path; do
            e2e_clone_link "$path" "$base" "$phys" || continue
            printf '%s\n' "$path"
        done
    )
    printf '%s' "${found:+$found$E2E_NL}"
    [ -z "$found" ]
}

# e2e_clone_link LINK BASE PHYS: 0 when LINK's text names BASE and the link
# resolves (as e2e_audit_clone_links says) to PHYS or a path under it.
e2e_clone_link() {
    local text target dir
    text=$(readlink "$1" 2>/dev/null) || return 1
    case $text in
        *"$2"*) ;;
        *) return 1 ;;
    esac
    case $text in
        /*) target=$text ;;
        *) target=${1%/*}/$text ;;
    esac
    if [ -d "$target" ]; then
        dir=$(cd -P -- "$target" 2>/dev/null && pwd -P) || return 1
    else
        dir=$(cd -P -- "${target%/*}" 2>/dev/null && pwd -P) || return 1
    fi
    case $dir in
        "$3" | "$3"/*) return 0 ;;
    esac
    return 1
}

# e2e_stow_paths PATH_VALUE: every executable named stow in the
# colon-separated PATH_VALUE, in PATH order, one per line.
e2e_stow_paths() {
    local rest=$1 dir
    while [ -n "$rest" ]; do
        dir=${rest%%:*}
        case $rest in
            *:*) rest=${rest#*:} ;;
            *) rest= ;;
        esac
        if [ -n "$dir" ] && [ -f "$dir/stow" ] && [ -x "$dir/stow" ]; then
            printf '%s\n' "$dir/stow"
        fi
    done
    return 0
}

# e2e_stow_start: set E2E_STOW_START to the stow executables on the system
# PATH and on the PATH a fresh `bash -l` reports, before any step ran: what
# the machine had before the flow (a runner may ship one).
e2e_stow_start() {
    local out=$E2E_OUT/log/stow-start.out path=''
    local run=()
    e2e_login_env
    [ -z "${E2E_TIMEOUT_BIN:-}" ] || run=("$E2E_TIMEOUT_BIN" "$E2E_TIMEOUT_CHECK")
    if (cd "$HOME" && exec ${run[@]+"${run[@]}"} "${E2E_LOGIN_ENV[@]}" bash -lc 'printf "E2E_PATH=%s\n" "$PATH"') \
        </dev/null >"$out" 2>"$E2E_OUT/log/stow-start.err"; then
        path=$(e2e_login_text "$out" | sed -n 's/^E2E_PATH=//p' | sed -n 1p)
    fi
    E2E_STOW_START=$(e2e_stow_paths "$E2E_SYS_PATH${path:+:$path}")
}

# e2e_audit_login_stow OUT ERR: every stow executable on the PATH of a fresh
# login shell (e2e_login_run) that the machine did not have before the flow
# (E2E_STOW_START), one per line. Nothing the native flow runs installs
# Stow (core.Brewfile and the hpc login env have no stow), so any is a
# finding. 0 when there is none; 2 when the login shell printed no PATH.
e2e_audit_login_stow() {
    local rc=0 path new line
    e2e_login_run "$1" "$2" 'printf "E2E_PATH=%s\n" "$PATH"' || rc=$?
    path=$(e2e_login_text "$1" | sed -n 's/^E2E_PATH=//p' | sed -n 1p)
    if [ "$rc" != 0 ] || [ -z "$path" ]; then
        printf 'the login shell exited %s and printed no PATH\n' "$rc"
        return 2
    fi
    new=$(e2e_stow_paths "$path" | while IFS= read -r line; do
        case $E2E_NL$E2E_STOW_START$E2E_NL in
            *"$E2E_NL$line$E2E_NL"*) ;;
            *) printf '%s\n' "$line" ;;
        esac
    done)
    printf '%s' "${new:+$new$E2E_NL}"
    [ -z "$new" ]
}

# e2e_audit_no_sudo LOG: on a host without sudo (E2E_SUDO=no: the clusters,
# where the denying wrapper stands in), every sudo line of wrappers.log is a
# finding, whatever its phase: a bootstrap step reached for root it cannot
# have. 0 when there are none.
e2e_audit_no_sudo() {
    local bad
    bad=$(awk -F '\t' '$3 == "sudo"' "$1" 2>/dev/null)
    printf '%s\n' "$bad"
    [ -z "$bad" ]
}

# e2e_audit_sudo_log TIMELINE SUDOLOG: every sudo.log entry ("Oct 10
# 03:14:15 2026 : user : TTY=... ; COMMAND=...", Defaults log_year) must be
# stamped inside a human:* or negative:* window of the timeline. A long
# entry continues on indented lines, which are skipped; any other line that
# is not a timestamped entry fails the audit, so a sudo.log in a shape the
# audit does not understand (no log_year, log_format json) cannot pass
# vacuously. Prints the entries outside every window and the lines it could
# not parse. Returns 0 (all inside), 1 (one outside, or a line that does not
# parse) or 2 without GNU date -d (macOS, where no sudo.log exists).
e2e_audit_sudo_log() {
    local windows='' t kind phase begin='' line stamp epoch inside bad='' rest window b e
    date -d @0 +%s >/dev/null 2>&1 || return 2
    while IFS=$E2E_TAB read -r t kind phase; do
        case $phase in
            human:* | negative:*) ;;
            *) continue ;;
        esac
        case $kind in
            begin) begin=$t ;;
            end)
                [ -z "$begin" ] || windows="$windows$begin $t $phase$E2E_NL"
                begin=''
                ;;
        esac
    done <"$1"
    while IFS= read -r line || [ -n "$line" ]; do
        case $line in
            '' | ' '* | "$E2E_TAB"*) continue ;; # a long entry's indented continuation
        esac
        if ! e2e_has '^[A-Z][a-z]{2} +[0-9]{1,2} [0-9]{2}:[0-9]{2}:[0-9]{2} [0-9]{4} : ' "$line"; then
            bad="$bad${bad:+$E2E_NL}unparsed entry: $line"
            continue
        fi
        stamp=$(printf '%s\n' "$line" | awk '{ print $1, $2, $3, $4 }')
        if ! epoch=$(date -d "$stamp" +%s 2>/dev/null); then
            bad="$bad${bad:+$E2E_NL}unparsed timestamp: $line"
            continue
        fi
        inside=0
        rest=$windows
        while [ -n "$rest" ]; do
            window=${rest%%"$E2E_NL"*}
            rest=${rest#*"$E2E_NL"}
            b=${window%% *}
            e=${window#* }
            e=${e%% *}
            if [ "$epoch" -ge "$b" ] && [ "$epoch" -le "$e" ]; then
                inside=1
                break
            fi
        done
        [ "$inside" = 1 ] || bad="$bad${bad:+$E2E_NL}outside every human/negative window: $line"
    done <"$2"
    printf '%s\n' "$bad"
    [ -z "$bad" ]
}
