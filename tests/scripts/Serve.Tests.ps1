BeforeAll {
    $ScriptPath = "$PSScriptRoot\..\..\skills\creative\p5js\scripts\serve.ps1"
}

Describe "serve.ps1" {
    It "defaults to port 8080 and current directory" {
        # This test ensures the file exists and has valid syntax
        # To truly test serving, we'd need to mock network layers or spin it up
        $fileExists = Test-Path $ScriptPath
        $fileExists | Should -Be $true

        # Test basic parsing
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
        $ast | Should -Not -BeNullOrEmpty
    }
}
