# Shell configuration

These files configure Bash, PowerShell, and Starship for the current Windows user.

## Set up another Windows computer

Install Git for Windows and PowerShell 7, then run these commands from this folder:

```powershell
pwsh -File .\Install-Tools.ps1
pwsh -File .\Sync-Configs.ps1 -Mode Apply
```

`Install-Tools.ps1` installs `bat` with winget and ble.sh under
`%USERPROFILE%\.local\share\blesh`. `Sync-Configs.ps1` backs up existing
destination files before applying the repository configurations, including
`.blerc` and the Bash `bat.sh` settings. Open a new terminal after setup so the
updated PATH and shell configuration take effect.

The Bash configuration expects ble.sh at the standard per-user path above. Its
loading is conditional, so Bash still starts if ble.sh is absent; `.blerc` then
has no effect until ble.sh is installed.
