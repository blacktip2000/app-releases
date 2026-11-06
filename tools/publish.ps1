# Publish an app installer to blacktip2000/app-releases and update apps/<App>/latest.json
# Usage: powershell -ExecutionPolicy Bypass -File tools\publish.ps1 -App CCCAN -Version 0.3.0 -Installer path\to\Setup.exe -NotesFile notes.md
#        [-LinuxX64 path\to\cccan_0.3.0_amd64.deb] [-LinuxArm64 path\to\cccan_0.3.0_arm64.deb]
#
# Notes file (UTF-8 markdown). Optional summary section at the top, shown first in the app's update dialog:
#   ### <summary heading: Korean "yoyak" (U+C694 U+C57D) or "Summary">
#   - one-line change
#   - ...
#   ### Added
#   - **Feature**: details
# Manifest fields: summary (from the summary section), history (summaries of previous versions from apps/<App>/versions/*.json).
# This script file stays ASCII-only (Windows PowerShell 5.1 reads BOM-less scripts as ANSI).
param(
    [Parameter(Mandatory = $true)][string]$App,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$Installer,
    [Parameter(Mandatory = $true)][string]$NotesFile,
    [string]$Repo = "blacktip2000/app-releases",
    [string]$ManifestName = "latest.json",
    [int]$HistoryCount = 10,
    [string]$LinuxX64 = "",
    [string]$LinuxArm64 = "",
    [switch]$ManifestOnly  # rebuild manifest for an already released version (no new release / asset)
)
$ErrorActionPreference = "Continue"  # native tools write warnings to stderr; check $LASTEXITCODE instead
$root = Split-Path -Parent $PSScriptRoot

if ($App -notmatch '^[A-Za-z0-9_-]+$') { throw "invalid app name: $App" }
if ($Version -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z.-]+)?$') { throw "invalid SemVer: $Version" }
if (-not (Test-Path $Installer)) { throw "installer not found: $Installer" }
if (-not (Test-Path $NotesFile)) { throw "notes file not found: $NotesFile" }

$KoSummary = -join [char[]](0xC694, 0xC57D)                                          # Korean "summary"
$KoPrev = -join [char[]](0xC774, 0xC804, 0x20, 0xBC84, 0xC804, 0x20, 0xC694, 0xC57D)  # Korean "previous version summary"

function Get-Summary([string]$text) {
    $out = New-Object System.Collections.Generic.List[string]
    $in = $false
    foreach ($l in ($text -split "`r?`n")) {
        if ($l -match '^#+\s*(.+?)\s*$') {
            $h = $Matches[1].ToLowerInvariant()
            $in = ($h -eq $KoSummary) -or ($h -eq 'summary') -or ($h -eq 'highlights')
            continue
        }
        if ($in -and $l -match '^[-*]\s+(.+)$') {
            $t = ($Matches[1] -replace '\*\*', '' -replace '`', '').Trim()
            if ($t) { $out.Add($t) }
        }
    }
    return , $out.ToArray()
}

$inst = Get-Item $Installer
$name = $inst.Name
if ($name -notmatch '^[A-Za-z0-9._-]+\.exe$') { throw "installer file name must be [A-Za-z0-9._-]+.exe: $name" }
$sha = (Get-FileHash $inst.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$size = $inst.Length
$tag = "$App-v$Version"

# platform key -> file (windows-x64 is the -Installer)
$assets = [ordered]@{ "windows-x64" = $inst }
foreach ($p in @(@("linux-x64", $LinuxX64), @("linux-arm64", $LinuxArm64))) {
    if ($p[1]) {
        if (-not (Test-Path $p[1])) { throw "package not found: $($p[1])" }
        $f = Get-Item $p[1]
        if ($f.Name -notmatch '^[A-Za-z0-9._+-]+\.deb$') { throw "linux package name must be *.deb: $($f.Name)" }
        $assets[$p[0]] = $f
    }
}
$notesMd = [IO.File]::ReadAllText((Resolve-Path $NotesFile), [Text.Encoding]::UTF8)
$summary = Get-Summary $notesMd
$appDir = Join-Path $root "apps\$App"
New-Item -ItemType Directory -Force -Path (Join-Path $appDir "versions") | Out-Null

# history: previous versions (newest first)
$history = @()
$prev = Get-ChildItem (Join-Path $appDir "versions") -Filter *.json -ErrorAction SilentlyContinue |
    Where-Object { $_.BaseName -match '^\d+\.\d+\.\d+$' -and $_.BaseName -ne $Version -and [version]$_.BaseName -lt [version]($Version -replace '-.*$', '') } |
    Sort-Object { [version]$_.BaseName } -Descending | Select-Object -First $HistoryCount
foreach ($f in $prev) {
    $v = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $s = @()
    if ($v.summary) { $s = @($v.summary) }
    $n = [string]$v.notes
    $cut = $n.IndexOf("`n### $KoPrev")
    if ($cut -ge 0) { $n = $n.Substring(0, $cut) }
    if (-not $s.Count) { $s = Get-Summary $n }
    $e = [ordered]@{ version = [string]$v.version; published = [string]$v.published; summary = @($s) }
    if (-not $s.Count) { $e.notes = $(if ($n.Length -gt 2000) { $n.Substring(0, 2000) } else { $n }) }
    $history += $e
}

# manifest notes: plain-ish text (old apps show it raw) + previous version summaries for apps that only read "notes"
$notes = ($notesMd -replace '\*\*', '' -replace '`', '').TrimEnd()
if ($notes.Length -gt 6000) { $notes = $notes.Substring(0, 6000) + "`n..." }
$prevLines = @()
foreach ($h in ($history | Select-Object -First 3)) {
    if ($h.summary.Count) {
        $prevLines += "v$($h.version)"
        foreach ($l in $h.summary) { $prevLines += "- $l" }
    }
}
if ($prevLines.Count) { $notes += "`n`n### $KoPrev`n" + ($prevLines -join "`n") }

if (-not $ManifestOnly) {
    Write-Host "[1/4] release $tag ($($assets.Keys -join ', '))"
    $null = gh release view $tag -R $Repo 2>&1
    if ($LASTEXITCODE -eq 0) {
        # Never replace an asset: the download CDN may keep serving the old bytes, and clients verify SHA-256.
        throw "release $tag already exists. Publish a new version instead of replacing assets."
    }
    $files = @($assets.Values | ForEach-Object { $_.FullName })
    gh release create $tag @files -R $Repo --title "$App v$Version" --notes-file $NotesFile
    if ($LASTEXITCODE -ne 0) { throw "gh release failed" }
} else {
    Write-Host "[1/4] manifest only (release $tag must already exist)"
    $null = gh release view $tag -R $Repo 2>&1
    if ($LASTEXITCODE -ne 0) { throw "release $tag not found" }
}

Write-Host "[2/4] manifest (summary $($summary.Count), history $($history.Count))"
$published = Get-Date -Format "yyyy-MM-dd"
$existing = Join-Path $appDir "versions\$Version.json"
if ($ManifestOnly -and (Test-Path $existing)) { $published = ([IO.File]::ReadAllText($existing, [Text.Encoding]::UTF8) | ConvertFrom-Json).published }
$installers = [ordered]@{}
foreach ($k in $assets.Keys) {
    $f = $assets[$k]
    $installers[$k] = [ordered]@{
        url    = "https://github.com/$Repo/releases/download/$tag/$($f.Name)"
        sha256 = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        size   = $f.Length
    }
}
$manifest = [ordered]@{
    schema    = 1
    app       = $App
    version   = $Version
    tag       = $tag
    published = $published
    summary   = @($summary)
    notes     = $notes
    notesUrl  = "https://github.com/$Repo/releases/tag/$tag"
    history   = @($history)
    installer = [ordered]@{
        url    = "https://github.com/$Repo/releases/download/$tag/$name"
        sha256 = $sha
        size   = $size
    }
    installers = $installers
}
$json = $manifest | ConvertTo-Json -Depth 6
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($existing, $json, $utf8)
[IO.File]::WriteAllText((Join-Path $appDir $ManifestName), $json, $utf8)

Write-Host "[3/4] commit & push"
git -C $root pull -q --rebase 2>&1 | Out-Null
git -C $root add "apps/$App" "tools" 2>&1 | Out-Null
git -C $root commit -q -m "$App $Version ($ManifestName)" 2>&1 | Out-Null
git -C $root push -q 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "git push failed" }

Write-Host "[4/4] verify"
$url = "https://raw.githubusercontent.com/$Repo/main/apps/$App/$ManifestName"
for ($i = 0; $i -lt 12; $i++) {
    try {
        $m = Invoke-RestMethod -Uri $url -Headers @{ "Cache-Control" = "no-cache" }
        if ($m.version -eq $Version -and $m.installer.sha256 -eq $sha -and $m.published -eq $published) { Write-Host "OK: $url -> $Version"; exit 0 }
    } catch { }
    Start-Sleep -Seconds 10
}
Write-Warning "manifest not visible yet at $url (CDN cache up to ~5 min)"
