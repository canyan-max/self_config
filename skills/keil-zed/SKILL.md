---
name: keil-zed
description: 在 Windows 上为 Keil Cortex-M 工程配置 Zed 和 clangd，按 uvprojx Target 生成编译数据库，并提供 PowerShell 7 编译、重编译、烧录任务。用于从 VS Code/Git Bash 迁移、头文件找不到、硬件宏混用及迁移开发电脑。
---

# Keil 与 Zed

Keil 是固件编译和链接的依据；clangd 用于补全、跳转和诊断。不要通过修改业务代码或同时定义两个硬件宏来消除编辑器报错。

## 配置工程

完整复制本文件夹到工程的 `.agents/skills/keil-zed/`。使用 PowerShell 7 执行 [scripts/keil-zed.ps1](scripts/keil-zed.ps1)，不依赖 Git Bash、jq、uv2clangd.exe 或 VS Code 扩展。

先查看项目和 Target；多工程或多 Target 时明确选择，不猜测板型。示例：

```powershell
& ./.agents/skills/keil-zed/scripts/keil-zed.ps1 -Action List -Project MDK/template.uvprojx

& ./.agents/skills/keil-zed/scripts/keil-zed.ps1 -Action Setup `
    -Project MDK/template.uvprojx -Target MPPT_NEW_CS5622 `
    -UV4 'D:/software_config/keil_soft/keil_app/UV4/UV4.exe'
```

示例路径只是当前电脑的安装位置。新电脑使用实际 UV4.exe 路径；脚本尝试从同一 Keil 安装位置找到 ARMCLANG/include，从 TOOLS.INI 的 RTEPATH 定位工程指定版本的 CMSIS。无法推导时用 `-ArmInclude`、`-CmsisInclude` 明确提供路径，不下载或混用其他版本的库。CPU 从所选 Target 推导，无法推导时用 `-Cpu cortex-m0plus` 等 clang CPU 名称。

旧工程如果直接 include `cmsis_armcc.h`，clangd 不能解析 ARMCC5 的专用语法。确认属于这种情况后，Setup 加 `-ArmccCompat`：仅在分析数据库添加随附 assets/clangd-compat 路径，把该头转接到真实 CMSIS 的 GCC/Clang 内联实现。不要将适配目录加入 uvprojx，不伪造空的中断/寄存器函数。当前 MPPT 工程的 event.h 属于这种情况，需要开启。`-ArmccCompat:$false` 可关闭此选项；普通工程无需启用。

Setup 会生成：

- 根目录 `compile_commands.json`：只含当前 Target 的源文件、宏和绝对包含路径，供 clangd 自动发现。
- `.zed/settings.json`：项目级 clangd 参数，保留已有其他设置；已有文件修改前生成 `.bak`。
- `.zed/tasks.json`：每个 Target 的 Database、Build、Rebuild、Flash 任务；保留非 `Keil: ` 前缀的已有任务，修改前备份。
- `.zed/keil.local.json`：当前 Target 和本机路径，不应随工程提交或跨机器照搬。

在 Zed 命令面板中执行 `task: spawn`，选择 `Keil: Database [目标]` 切换编辑板型；必要时执行 `editor: restart language server`。Build/Rebuild/Flash 也会先为所选 Target 更新数据库。Database 不编译、不烧录；Build 只编译；Rebuild 全量编译；**只有 Flash 才下载到硬件，不因设置编辑器而执行它**。

也可以直接运行：

```powershell
& ./.agents/skills/keil-zed/scripts/keil-zed.ps1 -Action Database -Target MPPT_OLD_CS5653
& ./.agents/skills/keil-zed/scripts/keil-zed.ps1 -Action Build -Target MPPT_NEW_CS5622
```

任务使用 `C:/Program Files/PowerShell/7/pwsh.exe`。本机配置自动记住上次目标；从本工程以外调用时传 `-Root`。全工程任务锁避免两个 Target 同时改数据库或运行 Keil。日志在 `.zed/logs/`；Keil 返回 1 可能只有警告，脚本结合日志检查错误，不把“进程启动成功”当作编译成功。

## 检查报错

按顺序检查：数据库是否在 Zed 打开的工程根目录、当前文件是否在数据库中、arguments 是否只有所选板型的宏、工程 include 和 CMSIS 版本路径是否存在。数据库的 directory 是 uvprojx 所在目录，不是 `.vscode`。不要把目录作为 `--query-driver`，也不要手工定义 `__GNUC__` 或 `__CC_ARM` 伪装编译器。

使用本机 clangd 的 `--check=实际源文件 --compile-commands-dir=工程根目录` 验证，至少检查原报错文件和包含硬件条件编译的文件。再按需要执行 Keil Build 验证任务。clangd 通过不代表固件编译或板上功能通过。

clangd 的 check 模式还测试重构功能。如果日志只有 `tweak: SwapBinaryOperands ... replacement overlaps`，应与头文件/语法诊断区分：本机 clangd 23 在 calc_lib.c 的宏表达式触发过此重构测试问题，不要为绕过它修改固件算法或关闭正常诊断。

脚本支持常见 Keil Cortex-M C/C++ 工程的 Target、Group、File 的 Define/Undefine/IncludePath，以及禁用的组/文件；CMSIS CORE 从工程 RTE package 获取版本。分析 C 采用 C99，使用 ARMCLANG 标准库头；ARMCC5 固件仍由 Keil 原编译器编译。MiscControls 的 Keil 专用参数、特殊 Pack 条件/生成源、非 Cortex-M/特殊 ABI 不会被完整转换；遇到这些工程先核对真实编译日志并补充转换，不声称数据库完整复现了所有编译参数。不改变 uvprojx、优化等级或源文件。

## 迁移与版本管理

复制整个 skill 文件夹即可，不需要复制旧的三个工具。旧脚本可保留，但不要再用它覆盖根目录数据库；旧转换器可能混合所有 Target，旧脚本还会把结果搬到 `.vscode/`。

提交 skill、`.zed/settings.json`、`.zed/tasks.json`。忽略根目录数据库、`.zed/keil.local.json`、`.zed/keil.lock`、日志、备份和 `.cache/`。若 `.gitignore` 有 `*.json`，为两个可共享的 Zed 配置显式添加例外；不要强制跟踪本机绝对路径。跨电脑后重跑 Setup，跨工程后重新选择工程/Target，不复制旧数据库。

配置字段核对依据：[Zed C](https://zed.dev/docs/languages/c)、[Zed tasks](https://zed.dev/docs/tasks)、[语言服务器配置](https://zed.dev/docs/configuring-languages)。
