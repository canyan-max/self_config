[CmdletBinding()]
param(
    [ValidateSet('Setup', 'Database', 'Build', 'Rebuild', 'Flash', 'List')]
    [string]$Action = 'Database',
    [string]$Root = (Get-Location).Path,
    [string]$Project,
    [string]$Target,
    [string]$UV4,
    [string]$ArmInclude,
    [string]$CmsisInclude,
    [switch]$ArmccCompat,
    [string]$Cpu
)

# PowerShell 7 only. Keil compiles the firmware; clangd only analyzes it.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7 (pwsh.exe).' }
$Root = (Resolve-Path -LiteralPath $Root).Path
$zedDir = Join-Path $Root '.zed'
[IO.Directory]::CreateDirectory($zedDir) | Out-Null
$configPath = Join-Path $zedDir 'keil.local.json'

function Read-JsonMap([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    }
    return @{}
}
function Write-Json([string]$Path, $Value) {
    $json = ConvertTo-Json -InputObject $Value -Depth 50
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temp, $json + "`n", [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp }
    }
}
function Backup-File([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Copy-Item -LiteralPath $Path -Destination "$Path.$([guid]::NewGuid().ToString('N')).bak"
    }
}
function Full-Path([string]$Base, [string]$Path) {
    if ($Path -match '\$[({%]') { throw "Unexpanded Keil path variable: $Path" }
    return [IO.Path]::GetFullPath($Path, $Base).Replace('\', '/')
}
function Node-Text($Node, [string]$XPath) {
    if ($null -eq $Node) { return '' }
    $child = $Node.SelectSingleNode($XPath)
    if ($null -eq $child) { return '' }
    return $child.InnerText.Trim()
}
function Split-Defines([string]$Value) {
    # Do not split commas inside quoted string macro values.
    return @([regex]::Split($Value, ',(?=(?:[^"]*"[^"]*")*[^"]*$)|;') |
        ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

$lockPath = Join-Path $zedDir 'keil.lock'
try {
    $taskLock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
} catch { throw 'Another Keil/Zed operation is running. Wait for it to finish.' }
try {
    $config = Read-JsonMap $configPath
    if (!$Project) { $Project = $config['project'] }
    if (!$Target) { $Target = $config['target'] }
    if (!$UV4) { $UV4 = $config['uv4'] }
    if (!$ArmInclude) { $ArmInclude = $config['arm_include'] }
    if (!$CmsisInclude) { $CmsisInclude = $config['cmsis_include'] }
    if (!$Cpu -and $Target -ceq $config['target']) { $Cpu = $config['cpu'] }
    if (!$PSBoundParameters.ContainsKey('ArmccCompat') -and $config.ContainsKey('armcc_compat')) {
        $ArmccCompat = [bool]$config['armcc_compat']
    }
    if (!$Project) {
        $projects = @(Get-ChildItem -LiteralPath $Root -Filter '*.uvprojx' -File -Recurse |
            Where-Object { $_.FullName -notmatch '[\\/](output|\.git|\.agents)[\\/]' })
        if (1 -ne $projects.Count) { throw 'Specify -Project; project discovery is ambiguous or empty.' }
        $Project = $projects[0].FullName
    }
    $projectPath = Full-Path $Root $Project
    $projectDir = Split-Path -Parent $projectPath
    $xml = [xml](Get-Content -LiteralPath $projectPath -Raw)
    $targets = @($xml.SelectNodes('/Project/Targets/Target'))
    $names = @($targets | ForEach-Object { Node-Text $_ 'TargetName' })
    if ('List' -eq $Action) { $names; return }
    if (!$Target -and 1 -eq $names.Count) { $Target = $names[0] }
    if (!$Target -or $Target -notin $names) { throw "Select -Target from: $($names -join ', ')" }
    $selected = @($targets | Where-Object { (Node-Text $_ 'TargetName') -ceq $Target })
    if (1 -ne $selected.Count) { throw "Target name must be unique: $Target" }
    $targetNode = $selected[0]
    if (!$Cpu) {
        $cpuText = Node-Text $targetNode 'TargetOption/TargetCommonOption/Cpu'
        if ($cpuText -match 'CPUTYPE\("(Cortex-[^"]+)"\)') {
            $Cpu = $Matches[1].ToLowerInvariant().Replace('+', 'plus')
        } else { throw 'Cannot infer CPU. Supply -Cpu, for example cortex-m0plus.' }
    }
    if (!$ArmInclude -and $UV4) {
        $keilRoot = Split-Path -Parent (Split-Path -Parent $UV4)
        $candidate = Join-Path $keilRoot 'ARM/ARMCLANG/include'
        if (Test-Path -LiteralPath $candidate) { $ArmInclude = $candidate }
    }
    if (!$ArmInclude -or !(Test-Path -LiteralPath (Join-Path $ArmInclude 'stdint.h'))) {
        throw 'Set -ArmInclude to the installed Keil ARMCLANG/include directory containing stdint.h.'
    }
    $ArmInclude = Full-Path $Root $ArmInclude
    $analysisCompiler = Full-Path $ArmInclude '../bin/armclang.exe'
    if (!(Test-Path -LiteralPath $analysisCompiler)) { throw "Compiler not found: $analysisCompiler" }
    $cmsisPackage = $xml.SelectSingleNode('/Project/RTE/packages/package[@vendor="ARM" and @name="CMSIS"]')
    if (!$CmsisInclude -and $null -ne $cmsisPackage -and $UV4) {
        $toolsIni = Join-Path (Split-Path -Parent (Split-Path -Parent $UV4)) 'TOOLS.INI'
        if (Test-Path -LiteralPath $toolsIni) {
            # Read only the pack path; TOOLS.INI can contain private license data.
            $packLine = Get-Content -LiteralPath $toolsIni | Where-Object { $_ -match '^RTEPATH=' } | Select-Object -First 1
            if ($packLine) {
                $packRoot = ($packLine -replace '^RTEPATH=', '').Trim().Trim('"')
                $CmsisInclude = Join-Path $packRoot "ARM/CMSIS/$($cmsisPackage.GetAttribute('version'))/CMSIS/Core/Include"
            }
        }
    }
    if ($null -ne $cmsisPackage -and (!$CmsisInclude -or !(Test-Path -LiteralPath $CmsisInclude))) {
        throw 'Project uses CMSIS. Supply -CmsisInclude matching its Keil pack version.'
    }
    if ($CmsisInclude) { $CmsisInclude = Full-Path $Root $CmsisInclude }
    $database = [Collections.Generic.List[object]]::new()
    $seenFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($group in $targetNode.SelectNodes('Groups/Group')) {
        if ('0' -eq (Node-Text $group 'GroupOption/CommonProperty/IncludeInBuild')) { continue }
        foreach ($file in $group.SelectNodes('Files/File')) {
            if ('0' -eq (Node-Text $file 'FileOption/CommonProperty/IncludeInBuild')) { continue }
            $filePath = Full-Path $projectDir (Node-Text $file 'FilePath')
            if ([IO.Path]::GetExtension($filePath) -notin @('.c', '.cpp', '.cc', '.cxx')) { continue }
            if (!$seenFiles.Add($filePath)) { throw "Duplicate source with ambiguous flags: $filePath" }
            if (!(Test-Path -LiteralPath $filePath)) { throw "Source not found: $filePath" }
            $argsList = [Collections.Generic.List[string]]::new()
            foreach ($arg in @($analysisCompiler, '--target=arm-none-eabi', "-mcpu=$Cpu", '-mthumb')) {
                $argsList.Add($arg)
            }
            if ('.c' -eq [IO.Path]::GetExtension($filePath)) {
                $argsList.Add('-std=c99')
            }
            $argsList.Add('-fms-extensions')
            $argsList.Add('-isystem'); $argsList.Add($ArmInclude)
            if ($ArmccCompat) {
                $compatInclude = Full-Path $PSScriptRoot '../assets/clangd-compat'
                if (!(Test-Path -LiteralPath $compatInclude)) { throw 'Missing skill compatibility headers; copy the complete skill.' }
                $argsList.Add('-I'); $argsList.Add($compatInclude)
            }
            if ($CmsisInclude) { $argsList.Add('-I'); $argsList.Add($CmsisInclude) }
            $rteInclude = Join-Path $projectDir "RTE/_$Target"
            if (Test-Path -LiteralPath $rteInclude) { $argsList.Add('-I'); $argsList.Add($rteInclude) }
            $controls = @(
                $targetNode.SelectSingleNode('TargetOption/TargetArmAds/Cads/VariousControls'),
                $group.SelectSingleNode('GroupOption/GroupArmAds/Cads/VariousControls'),
                $file.SelectSingleNode('FileOption/FileArmAds/Cads/VariousControls')
            )
            foreach ($control in $controls) {
                foreach ($define in (Split-Defines (Node-Text $control 'Define'))) { $argsList.Add("-D$define") }
                foreach ($undefine in (Split-Defines (Node-Text $control 'Undefine'))) { $argsList.Add("-U$undefine") }
                foreach ($include in ((Node-Text $control 'IncludePath') -split ';')) {
                    if ($include.Trim()) {
                        $includePath = Full-Path $projectDir $include.Trim().Trim('"')
                        if (!(Test-Path -LiteralPath $includePath -PathType Container)) {
                            throw "Include directory not found: $includePath"
                        }
                        $argsList.Add('-I'); $argsList.Add($includePath)
                    }
                }
            }
            $argsList.Add('-c'); $argsList.Add($filePath)
            $database.Add(@{ directory = $projectDir.Replace('\', '/'); file = $filePath; arguments = $argsList.ToArray() })
        }
    }
    if (0 -eq $database.Count) { throw "No C/C++ sources in target: $Target" }
    Write-Json (Join-Path $Root 'compile_commands.json') $database.ToArray()
    $config = @{
        project = [IO.Path]::GetRelativePath($Root, $projectPath).Replace('\', '/')
        target = $Target; uv4 = $UV4; arm_include = $ArmInclude; cmsis_include = $CmsisInclude; cpu = $Cpu
        armcc_compat = [bool]$ArmccCompat
    }
    Write-Json $configPath $config
    Write-Host "clangd: $Target, $($database.Count) sources -> root compile_commands.json"

    if ('Setup' -eq $Action) {
        $settingsPath = Join-Path $zedDir 'settings.json'
        $settings = Read-JsonMap $settingsPath
        if (!$settings.ContainsKey('lsp')) { $settings['lsp'] = @{} }
        if (!$settings.lsp.ContainsKey('clangd')) { $settings.lsp['clangd'] = @{} }
        if (!$settings.lsp.clangd.ContainsKey('binary')) { $settings.lsp.clangd['binary'] = @{} }
        $existingArgs = @($settings.lsp.clangd.binary['arguments'] | Where-Object {
            $_ -and $_ -notlike '--compile-commands-dir*'
        })
        $settings.lsp.clangd.binary['arguments'] = @(
            $existingArgs + @('--background-index', '--header-insertion=never') | Select-Object -Unique
        )
        Backup-File $settingsPath
        Write-Json $settingsPath $settings
        $tasksPath = Join-Path $zedDir 'tasks.json'
        $tasks = @()
        if (Test-Path -LiteralPath $tasksPath) {
            $tasks = @(Get-Content -LiteralPath $tasksPath -Raw | ConvertFrom-Json -AsHashtable |
                ForEach-Object { $_ } | Where-Object { $_['label'] -notlike 'Keil: *' })
        }
        $relativeScript = [IO.Path]::GetRelativePath($Root, $PSCommandPath).Replace('\', '/')
        if ($relativeScript.StartsWith('../')) { throw 'Copy the complete skill inside this project before Setup.' }
        foreach ($name in $names) {
            foreach ($operation in @('Database', 'Build', 'Rebuild', 'Flash')) {
                $quotedName = $name.Replace("'", "''")
                $taskCommand = '& ''C:/Program Files/PowerShell/7/pwsh.exe'' -NoProfile -File "' +
                    '$ZED_WORKTREE_ROOT/' + $relativeScript + '" -Root "$ZED_WORKTREE_ROOT" -Action ' +
                    $operation + " -Target '$quotedName'"
                $tasks += @{
                    label = "Keil: $operation [$name]"
                    command = $taskCommand
                    cwd = '$ZED_WORKTREE_ROOT'
                    shell = @{ program = 'C:/Program Files/PowerShell/7/pwsh.exe' }
                    allow_concurrent_runs = $false; use_new_terminal = $false
                    reveal = 'always'; hide = 'never'; save = 'all'
                }
            }
        }
        Backup-File $tasksPath
        Write-Json $tasksPath $tasks
        Write-Host 'Zed project settings/tasks created. Restart the clangd language server in Zed.'
    }

    if ($Action -in @('Build', 'Rebuild', 'Flash')) {
        if (!$UV4 -or !(Test-Path -LiteralPath $UV4 -PathType Leaf)) { throw 'Set -UV4 to the installed UV4.exe.' }
        $mode = switch ($Action) { 'Build' { '-b' }; 'Rebuild' { '-r' }; 'Flash' { '-f' } }
        $logDir = Join-Path $zedDir 'logs'
        [IO.Directory]::CreateDirectory($logDir) | Out-Null
        $safeTarget = $Target -replace '[^a-zA-Z0-9_.-]', '_'
        $logPath = Join-Path $logDir "$safeTarget-$Action.log"
        if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath }
        # Start-Process joins ArgumentList; quote path and target explicitly.
        foreach ($value in @($projectPath, $Target, $logPath)) {
            if ($value.Contains('"')) { throw 'Keil arguments may not contain double quotes.' }
        }
        $processArgs = "-j0 $mode `"$projectPath`" -t `"$Target`" -o `"$logPath`""
        $process = Start-Process -FilePath $UV4 -ArgumentList $processArgs -WorkingDirectory $projectDir -WindowStyle Hidden -PassThru
        $process.WaitForExit()
        if (!(Test-Path -LiteralPath $logPath)) { throw "Keil produced no log (exit $($process.ExitCode))." }
        $log = Get-Content -LiteralPath $logPath -Raw
        Write-Host $log
        if ($process.ExitCode -notin @(0, 1) -or $log -match '\b[1-9][0-9]* Error\(s\)') {
            throw "Keil $Action failed (exit $($process.ExitCode)). Log: $logPath"
        }
        if ('Flash' -ne $Action -and $log -notmatch '\b0 Error\(s\)') {
            throw "Build result could not be verified. Log: $logPath"
        }
        if ('Flash' -eq $Action -and ($log -match '(?im)\b(error:|failed\b|cannot\b)' -or
                $log -notmatch '(?i)Flash Load finished')) {
            throw "Flash completion could not be verified. Log: $logPath"
        }
        Write-Host "Keil $Action finished: $Target. Log: $logPath"
    }
} finally {
    if ($null -ne $taskLock) { $taskLock.Dispose() }
}
