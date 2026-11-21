#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Preview', 'Apply', 'Capture')]
    [string]$Mode = 'Preview',
    [string]$TargetHome = $env:USERPROFILE,
    [string]$BackupRoot = 'D:\codex-temp\self-config-sync\backups'
)

$ErrorActionPreference = 'Stop'
$TargetHome = [System.IO.Path]::GetFullPath($TargetHome)
$isCurrentUser = $TargetHome.TrimEnd('\') -ieq $env:USERPROFILE.TrimEnd('\')
$documents = if ($isCurrentUser) {
    [Environment]::GetFolderPath('MyDocuments')
} else {
    Join-Path $TargetHome 'Documents'
}
$starshipConfig = if ($isCurrentUser -and $env:STARSHIP_CONFIG) {
    $env:STARSHIP_CONFIG
} else {
    Join-Path $TargetHome '.config\starship.toml'
}
$mapping = [ordered]@{
    'bash\.bashrc' = Join-Path $TargetHome '.bashrc'
    'bash\.bash_profile' = Join-Path $TargetHome '.bash_profile'
    'bash\.blerc' = Join-Path $TargetHome '.blerc'
    'bash\.bashrc.d\bat.sh' = Join-Path $TargetHome '.bashrc.d\bat.sh'
    'bash\.bashrc.d\conv.sh' = Join-Path $TargetHome '.bashrc.d\conv.sh'
    'powershell\Microsoft.PowerShell_profile.ps1' = Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1'
    'starship\starship.toml' = $starshipConfig
}

if ($Mode -eq 'Preview') {
    foreach ($entry in $mapping.GetEnumerator()) {
        [pscustomobject]@{
            Repository = Join-Path $PSScriptRoot $entry.Key
            ActiveConfig = $entry.Value
        }
    }
    return
}

$operations = foreach ($entry in $mapping.GetEnumerator()) {
    $repoPath = Join-Path $PSScriptRoot $entry.Key
    [pscustomobject]@{
        RelativePath = $entry.Key
        Source = if ($Mode -eq 'Apply') { $repoPath } else { $entry.Value }
        Destination = if ($Mode -eq 'Apply') { $entry.Value } else { $repoPath }
    }
}

# Validate every source and back up every existing destination before any overwrite.
foreach ($operation in $operations) {
    if (-not (Test-Path -LiteralPath $operation.Source -PathType Leaf)) {
        throw "Configuration source not found: $($operation.Source)"
    }
    if (Test-Path -LiteralPath $operation.Destination -PathType Container) {
        throw "Configuration destination is a directory: $($operation.Destination)"
    }
}
$backupDirectory = Join-Path $BackupRoot (
    '{0}-{1}-{2}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Mode, [guid]::NewGuid().ToString('N')
)
foreach ($operation in $operations) {
    if (Test-Path -LiteralPath $operation.Destination -PathType Leaf) {
        $backupFile = Join-Path $backupDirectory $operation.RelativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $backupFile) -Force | Out-Null
        Copy-Item -LiteralPath $operation.Destination -Destination $backupFile
    }
}
foreach ($operation in $operations) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $operation.Destination) -Force | Out-Null
    Copy-Item -LiteralPath $operation.Source -Destination $operation.Destination -Force
    Write-Host "$Mode`: $($operation.Destination)"
}
if (Test-Path -LiteralPath $backupDirectory) {
    Write-Host "Backup: $backupDirectory"
}
