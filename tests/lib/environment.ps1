# Test-only counterpart of environment.sh; retain explicit DOTFILES_TEST_* fixture inputs.
foreach ($testName in @(Get-ChildItem Env: | Select-Object -ExpandProperty Name)) {
    if ($testName -match '^_?(DOTFILES|AWESOME_SKILLS|CODING_AGENT_KIT)_' -and $testName -notlike 'DOTFILES_TEST_*') {
        Remove-Item -LiteralPath "Env:$testName" -ErrorAction Stop
    }
}
Remove-Item Env:XDG_STATE_HOME, Env:XDG_DATA_HOME -ErrorAction Ignore

function Clear-DotfilesTestGitEnvironment {
    foreach ($testName in @(Get-ChildItem Env: | Where-Object Name -Like 'GIT_*' | Select-Object -ExpandProperty Name)) {
        Remove-Item -LiteralPath "Env:$testName" -ErrorAction Stop
        if (Test-Path -LiteralPath "Env:$testName") { throw "Environment override was not removed: $testName" }
    }
}
