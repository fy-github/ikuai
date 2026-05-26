param(
  [string]$PackageSource = "package\nullclaw",
  [string]$OutputDirectory = "output",
  [string]$StagingDirectory = ".tmp\build",
  [string]$BuildTime = ""
)

$ErrorActionPreference = "Stop"

function Fail($Message) {
  Write-Error $Message
  exit 1
}

function Format-SizeLabel([long]$Bytes) {
  if ($Bytes -lt 1KB) {
    return "$Bytes B"
  }
  if ($Bytes -lt 1MB) {
    return ([math]::Ceiling($Bytes / 1KB)).ToString() + "KB"
  }
  return ([math]::Round($Bytes / 1MB, 2)).ToString() + "MB"
}

function Write-Utf8NoBomFile([string]$Path, [string]$Content) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$manifestPath = Join-Path $PackageSource "manifest.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  Fail "Missing manifest: $manifestPath"
}

$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.name -ne "nullclaw") {
  Fail "manifest.name must be nullclaw"
}

$version = [string]$manifest.version
if (-not $version -or $version -match "latest" -or $version -notmatch "^\d+\.\d+\.\d+$") {
  Fail "manifest.version must be numeric xx.xx.xx format"
}

$image = [string]$manifest.image
if (-not $image -or $image -notmatch ":([^/:]+)$") {
  Fail "manifest.image must include a concrete tag"
}

$imageVersion = $Matches[1]
if ($imageVersion -match "latest") {
  Fail "manifest.image must not use latest"
}

$sourceVersion = $imageVersion -replace "^v", ""
$releaseVersion = "v$version"

if (-not $BuildTime) {
  $BuildTime = Get-Date -Format "yyyyMMddHHmmss"
}

if ($BuildTime -notmatch "^\d{14}$") {
  Fail "BuildTime must use yyyyMMddHHmmss format"
}

$stageRoot = Join-Path $StagingDirectory "nullclaw-ipkg"
$stagePackage = Join-Path $stageRoot "nullclaw"

if (Test-Path -LiteralPath $stageRoot) {
  Remove-Item -LiteralPath $stageRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

Copy-Item -LiteralPath $PackageSource -Destination $stagePackage -Recurse -Force

$packagePath = Join-Path $OutputDirectory "nullclaw-$sourceVersion-$BuildTime-$releaseVersion.ipkg"
if (Test-Path -LiteralPath $packagePath) {
  Remove-Item -LiteralPath $packagePath -Force
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\verify-ipkg.ps1" -PackageSource $stagePackage
if ($LASTEXITCODE -ne 0) {
  Fail "source verification failed"
}

& tar.exe -czvf $packagePath -C $stageRoot nullclaw | Out-Host
if ($LASTEXITCODE -ne 0) {
  Fail "tar packaging failed"
}

$packageSizeLabel = Format-SizeLabel ((Get-Item -LiteralPath $packagePath).Length)
$stageManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $stagePackage "manifest.json") | ConvertFrom-Json
$stageManifest.requirements.storage = $packageSizeLabel
$stageManifestJson = $stageManifest | ConvertTo-Json -Depth 10
Write-Utf8NoBomFile -Path (Join-Path $stagePackage "manifest.json") -Content $stageManifestJson

Remove-Item -LiteralPath $packagePath -Force
& tar.exe -czvf $packagePath -C $stageRoot nullclaw | Out-Host
if ($LASTEXITCODE -ne 0) {
  Fail "tar repackaging failed"
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\verify-ipkg.ps1" -PackageSource $stagePackage -PackagePath $packagePath
if ($LASTEXITCODE -ne 0) {
  Fail "archive verification failed"
}

Write-Host "Built package: $packagePath"
