#!/bin/sh
# Native login update: one attempt per interactive session, no installation,
# receipts, retries or fallback writer. The home binding survives partial apply.

case $- in
    *i*) ;;
    *) return 0 2>/dev/null || exit 0 ;;
esac
[ -z "${_DOTFILES_CHECKED:-}" ] || return 0 2>/dev/null || exit 0

_dotfiles_native_update() (
    [ "${DOTFILES_AUTO_UPDATE:-1}" != 0 ] || return 0
    # Fixed paths also work before a source checkout/library can be located.
    if [ -e "$HOME/.config/dotfiles/maintenance" ] || [ -L "$HOME/.config/dotfiles/maintenance" ]; then
        return 0
    fi
    _df_marker=$HOME/.config/dotfiles/native
    [ -f "$_df_marker" ] && [ ! -L "$_df_marker" ] || return 1
    {
        IFS= read -r _df_version && IFS= read -r _df_home && IFS= read -r _df_source
    } <"$_df_marker" || return 1
    [ "$_df_version" = dotfiles-chezmoi-v1 ] || return 1
    case $_df_source in /*) ;; *) return 1 ;; esac
    [ -r "$_df_source/lib/chezmoi-guard.sh" ] || return 1
    # shellcheck source=lib/chezmoi-guard.sh
    . "$_df_source/lib/chezmoi-guard.sh"
    _df_source=$(dotfiles_native_source "$HOME") || return 1
    _df_home=$(CDPATH='' cd -P -- "$HOME" && pwd -P) || return 1
    # Lost or empty state would make apply treat a foreign target as a first
    # apply, so a missing or empty state database refuses the update.
    [ -f "$_df_home/.local/state/chezmoi/chezmoi.boltdb" ] &&
        [ -s "$_df_home/.local/state/chezmoi/chezmoi.boltdb" ] || return 1
    case $_df_source in
        *OneDrive*)
            printf '%s\n' '[dotfiles] [warn] Automatic update skipped for OneDrive; use the documented independent-clone procedure.' >&2
            return 0
            ;;
    esac
    _df_chezmoi=$(command -v chezmoi) || return 1
    command -v git >/dev/null 2>&1 || return 1

    # Prevent inherited repository selection or injected config from redirecting
    # the clean-tree check or native Git update. Keep ordinary SSH host config.
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
    unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
    export GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=false SSH_ASKPASS=false
    export GCM_INTERACTIVE=never GIT_SSH_VARIANT=ssh
    export GIT_SSH_COMMAND='ssh -oBatchMode=yes -oConnectTimeout=10 -oConnectionAttempts=1'
    export GIT_HTTP_LOW_SPEED_LIMIT=1 GIT_HTTP_LOW_SPEED_TIME=15
    # No credential helper or Git hook can prompt/run during unattended update.
    export GIT_CONFIG_COUNT=4
    export GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=
    export GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null
    export GIT_CONFIG_KEY_2=maintenance.auto GIT_CONFIG_VALUE_2=false
    export GIT_CONFIG_KEY_3=gc.auto GIT_CONFIG_VALUE_3=0
    [ "$(git -C "$_df_source" rev-parse --show-toplevel 2>/dev/null)" = "$_df_source" ] || return 1
    _df_dirty=$(git -C "$_df_source" -c core.fsmonitor=false status --porcelain --untracked-files=all --ignore-submodules=none 2>/dev/null) || return 1
    [ -z "$_df_dirty" ] || return 1

    # HOME plus all five native state paths and the working tree are explicit;
    # inherited XDG/chezmoi settings cannot redirect this home's update.
    export HOME="$_df_home"
    set -- --source "$_df_source" --working-tree "$_df_source" \
        --destination "$_df_home" --config "$_df_home/.config/chezmoi/chezmoi.toml" \
        --cache "$_df_home/.cache/chezmoi" \
        --persistent-state "$_df_home/.local/state/chezmoi/chezmoi.boltdb" \
        --mode=file --no-tty --error-on-conflict --less-interactive --no-pager --use-builtin-diff \
        --use-builtin-age=true --use-builtin-git=false --force=false
    # Native defaults rebase/autostash. Validate the effective nonsecret subset,
    # including old local configs, without dumping any source/config/secret data.
    _df_contract=$("$_df_chezmoi" "$@" execute-template \
        '{{ if and (eq .chezmoi.config.update.command "git") (eq (toJson .chezmoi.config.update.args) "[\"-c\",\"rebase.autoStash=false\",\"-c\",\"merge.autoStash=false\",\"pull\",\"--ff-only\",\"--no-rebase\",\"--no-autostash\",\"--no-recurse-submodules\"]") (not .chezmoi.config.update.recurseSubmodules) (not .chezmoi.config.git.autoadd) (not .chezmoi.config.git.autocommit) (not .chezmoi.config.git.autopush) }}safe{{ end }}' \
        </dev/null 2>/dev/null) || return 1
    [ "$_df_contract" = safe ] || return 1
    # Less-interactive also refuses preexisting new targets with no entry in
    # native state; error-on-conflict alone can silently adopt/overwrite them.
    # Transport timeouts bound normal network failures; builtin age and closed
    # stdin avoid unlock prompts. Native output is not a secret-redaction boundary.
    # Preserve shared parent modes. Missing parents require reviewed operator
    # preparation before an unattended update can apply their children.
    "$_df_chezmoi" "$@" update --apply --exclude=dirs --recurse-submodules=false </dev/null >/dev/null 2>&1
)

if ! _dotfiles_native_update; then
    printf '%s\n' '[dotfiles] [warn] Native update did not complete; inspect the binding, source, backend and destination privately before retrying.' >&2
fi
export _DOTFILES_CHECKED=1
unset -f _dotfiles_native_update
