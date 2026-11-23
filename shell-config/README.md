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

## 两台电脑同步

`git pull` 只更新仓库文件；执行 `./Sync-Configs.ps1 -Mode Apply` 才会更新当前用户正在使用的配置。更改共用配置后在仓库提交并推送，另一台电脑拉取后再次 Apply。

电脑专属路径放在 `~/.bashrc.local`，参考 `bash/.bashrc.local.example`。同步脚本不会覆盖或采集这个文件。标准安装路径下的 ble.sh 和 PATH 中的 bat 不需要额外配置；自定义安装位置可设置 `SELF_CONFIG_BLESH_PATH` 和 `SELF_CONFIG_BAT_DIR`。`cmphome`、`st` 的目标分别通过 `SELF_CONFIG_PROJECTS_HOME`、`SELF_CONFIG_ST_PROJECT` 设置，未设置时返回用户目录。

已经安装好工具的电脑直接 Apply 即可。新电脑才需要先执行安装脚本；没有 Starship 也能正常启动 Shell。工具安装脚本默认把临时文件放在 `D:\codex-temp\self-config-install`，没有 D 盘时通过 `-TempRoot` 指定现有磁盘上的目录。
