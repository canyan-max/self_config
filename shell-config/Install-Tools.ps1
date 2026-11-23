#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$TempRoot = 'D:\codex-temp\self-config-install'
)

$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
$env:TEMP = [System.IO.Path]::GetFullPath($TempRoot)
$env:TMP = $env:TEMP

if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw 'winget was not found. Install App Installer, then run this script again.'
}

if (-not (Get-Command bat.exe -ErrorAction SilentlyContinue)) {
    winget install --id sharkdp.bat --exact --scope user --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget could not install bat (exit code $LASTEXITCODE)."
    }
} else {
    Write-Host 'bat is already installed.'
}

$git = Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $git) {
    throw 'Git for Windows was not found. Install Git for Windows, then run this script again.'
}
$gitRoot = Split-Path (Split-Path $git.Source -Parent) -Parent
$bash = Join-Path $gitRoot 'bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) {
    throw "Git Bash was not found at $bash."
}

$bashHome = Join-Path $env:USERPROFILE '.local\share\blesh\ble.sh'
if (Test-Path -LiteralPath $bashHome -PathType Leaf) {
    Write-Host "ble.sh is already installed at $bashHome."
    return
}

$archive = Join-Path $env:TEMP 'ble-nightly.tar.xz'
Invoke-WebRequest -Uri 'https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz' -OutFile $archive

$installScript = @'
set -e
archive=$1
export TMPDIR=$(cygpath -u "$2")
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
tar -xJf "$archive" -C "$work"
bash "$work/ble-nightly/ble.sh" --install "$HOME/.local/share"
'@
& $bash --noprofile --norc -c $installScript self-config $archive $env:TEMP
if ($LASTEXITCODE -ne 0) {
    throw "ble.sh installation failed (exit code $LASTEXITCODE)."
}

Write-Host "Installed ble.sh under $env:USERPROFILE\.local\share\blesh."
Write-Host 'Open a new terminal to use the installed tools.'
