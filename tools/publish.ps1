# Publish an app installer to blacktip2000/app-releases and update apps/<App>/latest.json
# Usage: powershell -ExecutionPolicy Bypass -File tools\publish.ps1 -App CCCAN -Version 0.3.0 -Installer path\to\Setup.exe -NotesFile notes.md
param(
    [Parameter(Mandatory = $true)][string]$App,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$Installer,
    [Parameter(Mandatory = $true)][string]$NotesFile,
    [string]$Repo = "blacktip2000/app-releases",
    [string]$ManifestName = "latest.json"
)
$ErrorActionPreference = "Continue"  # native tools write warnings to stderr; check $LASTEXITCODE instead
$root = Split-Path -Parent $PSScriptRoot

if ($App -notmatch '^[A-Za-z0-9_-]+$') { throw "invalid app name: $App" }
if ($Version -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z.-]+)?$') { throw "invalid SemVer: $Version" }
if (-not (Test-Path $Installer)) { throw "installer not found: $Installer" }
if (-not (Test-Path $NotesFile)) { throw "notes file not found: $NotesFile" }

$inst = Get-Item $Installer
$name = $inst.Name
if ($name -notmatch '^[A-Za-z0-9._-]+\.exe$') { throw "installer file name must be [A-Za-z0-9._-]+.exe: $name" }
$sha = (Get-FileHash $inst.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$size = $inst.Length
$tag = "$App-v$Version"
$notes = [IO.File]::ReadAllText((Resolve-Path $NotesFile), [Text.Encoding]::UTF8)
if ($notes.Length -gt 6000) { $notes = $notes.Substring(0, 6000) + "`n..." }

Write-Host "[1/4] release $tag ($name, $size bytes, sha256 $sha)"
$null = gh release view $tag -R $Repo 2>&1
if ($LASTEXITCODE -eq 0) {
    # Never replace an asset: the download CDN may keep serving the old bytes, and clients verify SHA-256.
    throw "release $tag already exists. Publish a new version instead of replacing assets."
}
gh release create $tag $inst.FullName -R $Repo --title "$App v$Version" --notes-file $NotesFile
if ($LASTEXITCODE -ne 0) { throw "gh release failed" }

Write-Host "[2/4] manifest"
$manifest = [ordered]@{
    schema    = 1
    app       = $App
    version   = $Version
    tag       = $tag
    published = (Get-Date -Format "yyyy-MM-dd")
    notes     = $notes
    notesUrl  = "https://github.com/$Repo/releases/tag/$tag"
    installer = [ordered]@{
        url    = "https://github.com/$Repo/releases/download/$tag/$name"
        sha256 = $sha
        size   = $size
    }
}
$json = $manifest | ConvertTo-Json -Depth 5
$utf8 = New-Object Text.UTF8Encoding($false)
$appDir = Join-Path $root "apps\$App"
New-Item -ItemType Directory -Force -Path (Join-Path $appDir "versions") | Out-Null
[IO.File]::WriteAllText((Join-Path $appDir "versions\$Version.json"), $json, $utf8)
[IO.File]::WriteAllText((Join-Path $appDir $ManifestName), $json, $utf8)

Write-Host "[3/4] commit & push"
git -C $root pull -q --rebase 2>&1 | Out-Null
git -C $root add "apps/$App" 2>&1 | Out-Null
git -C $root commit -q -m "$App $Version ($ManifestName)" 2>&1 | Out-Null
git -C $root push -q 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "git push failed" }

Write-Host "[4/4] verify"
$url = "https://raw.githubusercontent.com/$Repo/main/apps/$App/$ManifestName"
for ($i = 0; $i -lt 12; $i++) {
    try {
        $m = Invoke-RestMethod -Uri $url -Headers @{ "Cache-Control" = "no-cache" }
        if ($m.version -eq $Version -and $m.installer.sha256 -eq $sha) { Write-Host "OK: $url -> $Version"; exit 0 }
    } catch { }
    Start-Sleep -Seconds 10
}
Write-Warning "manifest not visible yet at $url (CDN cache up to ~5 min)"
