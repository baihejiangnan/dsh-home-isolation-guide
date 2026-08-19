[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DshHome,

    [string]$Profile = "tauri",
    [string]$HostAddress = "127.0.0.1",
    [ValidateRange(1, 65535)]
    [int]$Port = 3081,
    [string]$DshCommand = "dsh",
    [switch]$InitializeOnly
)

$ErrorActionPreference = "Stop"
$resolvedParent = [System.IO.Path]::GetFullPath((Split-Path -Parent $DshHome))
$resolvedHome = [System.IO.Path]::GetFullPath($DshHome)

if ([string]::IsNullOrWhiteSpace($resolvedParent) -or $resolvedHome -eq $resolvedParent) {
    throw "Refusing unsafe DSH_HOME path: $resolvedHome"
}

if (Test-Path -LiteralPath $resolvedHome) {
    throw "DSH_HOME already exists. Choose a new empty path: $resolvedHome"
}

$profileDir = Join-Path $resolvedHome "profiles\$Profile"
New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

$manifest = [ordered]@{
    name = "dsh-profile-$Profile"
    private = $true
    dependencies = [ordered]@{}
    dsh = [ordered]@{
        profile = [ordered]@{
            bundles = @(
                "@deepseek-ai/dsh-base"
                "@deepseek-ai/dsh-web-app"
            )
        }
    }
}

$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
$manifestJson = ($manifest | ConvertTo-Json -Depth 8) + "`n"
[System.IO.File]::WriteAllText(
    (Join-Path $profileDir "package.json"),
    $manifestJson,
    $utf8WithoutBom
)
[System.IO.File]::WriteAllText(
    (Join-Path $profileDir "cordis.patch.yml"),
    "# Profile-local overrides belong here. An empty patch must be an array.`n[]`n",
    $utf8WithoutBom
)

Write-Host "Created isolated DSH_HOME: $resolvedHome"
Write-Host "Created profile: $Profile"

if ($InitializeOnly) {
    exit 0
}

$env:DSH_HOME = $resolvedHome
$env:DSH_TELEMETRY_DISABLED = "1"

& $DshCommand --profile $Profile --host $HostAddress --port $Port
exit $LASTEXITCODE
