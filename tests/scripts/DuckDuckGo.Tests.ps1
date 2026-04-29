BeforeAll {
    $ScriptPath = "$PSScriptRoot\..\..\optional-skills\research\duckduckgo-search\scripts\duckduckgo.ps1"
}

Describe "duckduckgo.ps1" {
    It "shows usage when no query is provided" {
        $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $ScriptPath 2>&1
        $output | Should -Match "Usage: .\duckduckgo.ps1 <query> \[max_results\]"
    }

    It "fails when ddgs is not installed" {
        # Mocking Get-Command to simulate ddgs not being installed is hard across process boundaries
        # So we test via mocking in the same runspace
        Mock Get-Command { return $false } -ParameterFilter { $Name -eq 'ddgs' }
        Mock Write-Error {}

        { & $ScriptPath "test query" } | Should -Throw
    }
}
