Invoke-Expression (&starship init powershell)

# PSReadLine: Tab accepts inline predictions, falling back to menu completion.
Import-Module PSReadLine

if($Host.UI.SupportsVirtualTerminal)
{
    Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView
}

Set-PSReadLineKeyHandler -Chord Tab -BriefDescription 'AcceptSuggestionOrComplete' -LongDescription 'Accept an inline prediction, or open completion when none is accepted.' -ScriptBlock {
    param($key, $arg)

    $lineBefore = $null
    $cursorBefore = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$lineBefore, [ref]$cursorBefore)
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptSuggestion($key, $arg)

    $lineAfter = $null
    $cursorAfter = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$lineAfter, [ref]$cursorAfter)
    if ($lineBefore -ceq $lineAfter -and $cursorBefore -eq $cursorAfter) {
        [Microsoft.PowerShell.PSConsoleReadLine]::MenuComplete($key, $arg)
    }
}
Set-PSReadLineKeyHandler -Chord 'Ctrl+Tab' -Function MenuComplete

# Search matching command history with the arrow keys.
Set-PSReadLineKeyHandler -Chord UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Chord DownArrow -Function HistorySearchForward

#Git alias
function gs  { git status }
function ga  { git add @args }
function gcm { git commit @args }
function glg { git log --oneline --graph --all }
function gb  { git branch @args }
function gce { git checkout @args }
function gpl { git pull @args }
function gps { git push @args }
function gft { git fetch @args }
function gk  { gitk }

# Keep completion failures quiet.
Set-PSReadLineOption -BellStyle None
