# shellcheck shell=bash
# Test-only isolation, including future upstream knobs. Keep deliberate inputs.
for _dotfiles_test_name in "${!DOTFILES_@}" "${!_DOTFILES_@}" \
    "${!AWESOME_SKILLS_@}" "${!_AWESOME_SKILLS_@}" \
    "${!CODING_AGENT_KIT_@}" "${!_CODING_AGENT_KIT_@}"; do
    case $_dotfiles_test_name in
        DOTFILES_TEST_* | DOTFILES_SYNC_PYTHON) ;;
        *) unset "$_dotfiles_test_name" ;;
    esac
done
unset _dotfiles_test_name XDG_STATE_HOME XDG_DATA_HOME

# Only suites that create fixture repositories call this before any Git.
dotfiles_test_clear_git_environment() {
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
        GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX
}
