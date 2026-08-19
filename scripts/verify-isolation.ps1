[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FirstHome,

    [Parameter(Mandatory = $true)]
    [string]$SecondHome
)

$ErrorActionPreference = "Stop"
$first = [System.IO.Path]::GetFullPath($FirstHome).TrimEnd('\', '/')
$second = [System.IO.Path]::GetFullPath($SecondHome).TrimEnd('\', '/')

if ([string]::Equals($first, $second, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The two DSH_HOME paths resolve to the same directory."
}

$statePaths = @(
    ".credentials.yaml",
    "settings.yaml",
    "sessions",
    ".agent-presets",
    "storages",
    "profiles"
)

$rows = foreach ($relative in $statePaths) {
    [pscustomobject]@{
        State = $relative
        First = Test-Path -LiteralPath (Join-Path $first $relative)
        Second = Test-Path -LiteralPath (Join-Path $second $relative)
    }
}

$rows | Format-Table -AutoSize
Write-Host "PASS: distinct roots mean DSH will address distinct state files."
