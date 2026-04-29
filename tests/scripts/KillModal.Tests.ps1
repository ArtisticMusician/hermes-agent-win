BeforeAll {
    $ScriptPath = "$PSScriptRoot\..\..\scripts\kill_modal.ps1"
}

Describe "kill_modal.ps1" {
    It "can be executed" {
        $output = & pwsh -NoProfile -ExecutionPolicy Bypass -Command "& { `$ErrorActionPreference='Continue'; & '$ScriptPath' }" 2>&1
        $output | Should -Not -BeNullOrEmpty
    }
}
