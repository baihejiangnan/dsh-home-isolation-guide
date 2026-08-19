[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceHome,

    [Parameter(Mandatory = $true)]
    [string]$TargetHome,

    [string]$Profile = "tauri"
)

$ErrorActionPreference = "Stop"
$sourceRoot = [System.IO.Path]::GetFullPath($SourceHome).TrimEnd('\', '/')
$targetRoot = [System.IO.Path]::GetFullPath($TargetHome).TrimEnd('\', '/')
$sourceProfile = Join-Path $sourceRoot "profiles\$Profile"
$targetProfile = Join-Path $targetRoot "profiles\$Profile"

if ([string]::Equals($sourceRoot, $targetRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "SourceHome and TargetHome must be different."
}

if (-not (Test-Path -LiteralPath (Join-Path $sourceProfile "package.json") -PathType Leaf)) {
    throw "Source profile manifest not found: $sourceProfile\package.json"
}

if (Test-Path -LiteralPath $targetRoot) {
    throw "TargetHome already exists. Choose a new path: $targetRoot"
}

New-Item -ItemType Directory -Path $targetProfile -Force | Out-Null
$sourcePrefixLength = $sourceProfile.Length

Get-ChildItem -LiteralPath $sourceProfile -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($sourcePrefixLength).TrimStart('\', '/')
    $segments = $relative -split '[\\/]'
    if ($segments -contains "node_modules") {
        return
    }

    $destination = Join-Path $targetProfile $relative
    $destinationParent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
    Copy-Item -LiteralPath $_.FullName -Destination $destination
}

Write-Host "Created isolated upgrade-test DSH_HOME: $targetRoot"
Write-Host "Copied profile definition: $Profile"
Write-Host "Excluded node_modules; install dependencies with the target DSH version before testing."
