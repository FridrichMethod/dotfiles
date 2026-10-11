# shellcheck shell=bash
# shellcheck disable=SC2034 # the guard state (E2E_STOWED, E2E_LOGIN_SHELL_START) is read by steps.sh and inside.sh
# The checks of tests/e2e/inside.sh that watch the home and the clone: the
# no-write snapshots (an empty TMPDIR, HOME by find -newer and entry count),
# the clean-clone rule, the per-step guards (rc-file digests, the stow
# state), the login-shell run and the acceptance audits (wrappers.log
# phases, sudo.log timestamps against the timeline). Sourced after
# common.sh; same portability rules (no find -printf, no stat, no date -d
# except inside the sudo.log audit, which Linux alone needs).

# Guard state: the before-images e2e_step_begin takes, the violations the
# audits report at the end, and the notes e2e_step_end appends after a row.
E2E_RC_FILES='.bashrc .profile .bash_profile .zshrc .zshenv .zprofile'
E2E_RC_BEFORE='' E2E_RC_VIOLATIONS=''
E2E_STOW_BEFORE='' E2E_STOW_VIOLATIONS='' E2E_STOWED=0
E2E_PENDING_NOTES=''
E2E_LOGIN_SHELL_START=''
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

# e2e_stow_state: "<state|->" "<link|->": whether ./stow-all.sh's state file
# ($(git rev-parse --git-path dotfiles-sync-unix) in the clone) and the
# ~/.zshrc link exist.
e2e_stow_state() {
    local state='-' link='-' path
    if [ -e "$E2E_CLONE/.git" ] &&
        path=$(git -C "$E2E_CLONE" rev-parse --git-path dotfiles-sync-unix 2>/dev/null </dev/null) &&
        [ -n "$path" ]; then
        case $path in
            /*) ;;
            *) path=$E2E_CLONE/$path ;;
        esac
        [ ! -f "$path" ] || state='state'
    fi
    [ ! -L "$HOME/.zshrc" ] || link='link'
    printf '%s %s\n' "$state" "$link"
}

e2e_guard_before() {
    E2E_RC_BEFORE=$(e2e_rc_sums)
    E2E_STOW_BEFORE=$(e2e_stow_state)
}

# e2e_guard_after STEP PHASE: compare with the before-images. The rc files
# may change during a human:* phase only (recorded as a note: the H7-stow
# block moves /etc/skel files aside and links the tracked ones); the stow
# state and the ~/.zshrc link may appear only during human:H7-stow, both at
# once, and never vanish.
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
    after=$(e2e_stow_state)
    if [ "$after" != "$E2E_STOW_BEFORE" ]; then
        if [ "$phase" = human:H7-stow ] && [ "$E2E_STOW_BEFORE" = '- -' ] && [ "$after" = 'state link' ]; then
            E2E_STOWED=1
        else
            E2E_STOW_VIOLATIONS="$E2E_STOW_VIOLATIONS${E2E_STOW_VIOLATIONS:+; }$step ($phase): $E2E_STOW_BEFORE -> $after"
        fi
    fi
}

# --- no-write snapshots ------------------------------------------------------

# e2e_prune_args: the find arguments that leave out what a snapshot must not
# count: the clone's .git (git status refreshes its index), E2E_OUT and
# E2E_SRC when they are under HOME, and E2E_SNAPSHOT_PRUNE (the mac runner's
# $HOME/work and $HOME/Library).
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
        "PATH=$E2E_SYS_PATH" DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0 GITSTATUS_AUTO_INSTALL=0
        "E2E_OUT=$E2E_OUT" "E2E_PHASE=${E2E_PHASE:--}")
}

# e2e_login_zsh: E2E_LOGIN_ZSH expanded (zsh on PATH, or the hpc login env's).
e2e_login_zsh() {
    e2e_expand "${E2E_LOGIN_ZSH:-zsh}"
}

# e2e_login_run OUT ERR COMMAND: bash -l, then the host's zsh as an
# interactive login shell running COMMAND, from that environment.
e2e_login_run() {
    local cmd
    cmd="exec $(e2e_quote "$(e2e_login_zsh)") -il -c $(e2e_quote "$3")"
    e2e_login_env
    e2e_run "$1" "$2" "$E2E_TIMEOUT_CHECK" "$HOME" "${E2E_LOGIN_ENV[@]}" bash -lc "$cmd"
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

# e2e_login_shell_check OUT ERR: the login shell must exit 0 and print
# nothing: stdout empty, stderr empty once the no-terminal lines of
# e2e_login_noise are dropped. E2E_LOGIN_DETAIL gets what it printed, with the
# known complaints (oh-my-zsh, the dotfiles hooks, not found, permission
# denied, [error]) quoted first.
e2e_login_shell_check() {
    local out=$1 err=$2 rc=0 noise findings
    e2e_login_run "$out" "$err" exit || rc=$?
    noise=$(e2e_login_noise "$err")
    findings=$(grep -E '^\[(oh-my-zsh|dotfiles|awesome-skills)\]|not found|[Pp]ermission denied|\[error\]' \
        "$out" "$err" 2>/dev/null) || true
    E2E_LOGIN_DETAIL="exit $rc"
    [ -z "$findings" ] || E2E_LOGIN_DETAIL="$E2E_LOGIN_DETAIL; findings: $(e2e_one_line "$findings" 300)"
    [ ! -s "$out" ] || E2E_LOGIN_DETAIL="$E2E_LOGIN_DETAIL; stdout: $(e2e_one_line "$(cat "$out")" 200)"
    [ -z "$noise" ] || E2E_LOGIN_DETAIL="$E2E_LOGIN_DETAIL; stderr: $(e2e_one_line "$noise" 200)"
    [ "$rc" = 0 ] && [ ! -s "$out" ] && [ -z "$noise" ]
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
# negative:*: a sudo, chsh or stow that ran where only the harness's own
# read-only steps should have. A bare `stow --version` or `stow -V` is not
# one: the doctor's tools.tsv probe runs it on every doctor run, and the
# wrapper logs the probe like any call. 0 when there are none.
e2e_audit_wrappers() {
    local bad
    bad=$(awk -F '\t' '$2 !~ /^(human|negative):/ && !($3 == "stow" && ($6 == "--version" || $6 == "-V"))' \
        "$1" 2>/dev/null)
    printf '%s\n' "$bad"
    [ -z "$bad" ]
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
# 03:14:15 2026 : user : TTY=... ; COMMAND=...", Defaults log_year; a long
# entry continues on indented lines) must be stamped inside a human:* or
# negative:* window of the timeline. Prints the entries outside every
# window. Returns 0 (all inside), 1 (one outside, or an entry that does not
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
        e2e_has '^[A-Z][a-z]{2} +[0-9]{1,2} [0-9]{2}:[0-9]{2}:[0-9]{2} [0-9]{4} : ' "$line" || continue
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
