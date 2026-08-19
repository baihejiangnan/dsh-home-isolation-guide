# DSH_HOME 隔离与全新实例复现指南

本仓库说明如何为 DeepSeek Harness（DSH）创建一个真正全新的状态环境，使它不共享已有 API Key、会话、设置、存储和用户 Agent 预设，并提供 PowerShell、Node.js 与 Rust 的可运行示例。

## 核心结论

隔离单位是 `DSH_HOME`，不是 profile 名称。

```text
旧实例                          新实例
C:\Users\you\.dsh              D:\dsh-instances\desktop-a
|-- .credentials.yaml           |-- profiles\tauri\package.json
|-- sessions\                   `-- profiles\tauri\cordis.patch.yml
`-- .agent-presets\
```

启动新实例时设置：

```text
DSH_HOME=D:\dsh-instances\desktop-a
dsh --profile tauri --host 127.0.0.1 --port 3081
```

DSH 之后产生的凭据、会话和预设都会落到新目录，不会从 `C:\Users\you\.dsh` 读取。

## 前置条件

- 已安装可用的 `dsh` 命令，或者知道 DSH CLI 的完整路径。
- Windows PowerShell 5.1+ 或 PowerShell 7+。
- Node.js 20+（仅 Node.js 示例需要）。
- Rust 1.77+（仅 Rust 示例需要）。

先确认：

```powershell
dsh --help
node --version
rustc --version
```

## 最快复现：PowerShell

从仓库根目录运行：

```powershell
.\examples\powershell\new-dsh-home.ps1 `
  -DshHome "D:\dsh-instances\desktop-a" `
  -Profile "tauri" `
  -Port 3081
```

脚本会：

1. 拒绝任何已经存在的目标目录。
2. 创建 `profiles\tauri`。
3. 写入 `dsh-base` 与 `dsh-web-app` bundle 清单。
4. 仅对子进程设置 `DSH_HOME`。
5. 启动 `http://127.0.0.1:3081`。

只初始化、不启动：

```powershell
.\examples\powershell\new-dsh-home.ps1 `
  -DshHome ".\.DSH_HOME\desktop-a" `
  -InitializeOnly
```

如果 `dsh` 不在 `PATH`：

```powershell
.\examples\powershell\new-dsh-home.ps1 `
  -DshHome "D:\dsh-instances\desktop-a" `
  -DshCommand "C:\path\to\dsh.cmd"
```

## Node.js 示例

```powershell
node .\examples\node\launcher.mjs "D:\dsh-instances\node-a" tauri 3082
```

可以通过 `DSH_BIN` 指定 CLI：

```powershell
$env:DSH_BIN = "C:\path\to\dsh.cmd"
node .\examples\node\launcher.mjs "D:\dsh-instances\node-a"
```

## Rust 示例

```powershell
cargo run --manifest-path .\examples\rust-launcher\Cargo.toml -- `
  "D:\dsh-instances\rust-a" tauri 3083
```

Rust 版本只使用标准库，可直接嵌入 Tauri 或其他桌面应用的后端。

## 验证隔离

验证两个根目录解析结果不同，并查看各状态入口是否存在：

```powershell
.\scripts\verify-isolation.ps1 `
  -FirstHome "C:\Users\you\.dsh" `
  -SecondHome "D:\dsh-instances\desktop-a"
```

重要：验证脚本不会读取 API Key、会话内容或设置内容，只检查路径与文件是否存在。

## 本机实际案例

在一次 Windows 桌面端集成中，原有 CLI 使用：

```text
C:\Users\<user>\.dsh
```

桌面应用改为使用其 AppData 专属目录：

```text
C:\Users\<user>\AppData\Roaming\<application-id>\data\dsh
```

应用启动 DSH 前执行等价逻辑：

```rust
let dsh_home = app_data_dir.join("data").join("dsh");
std::fs::create_dir_all(&dsh_home)?;

Command::new(dsh_binary)
    .args(["--profile", "tauri", "--host", "127.0.0.1", "--port", "3081"])
    .env("DSH_HOME", &dsh_home)
    .spawn()?;
```

结果：桌面端第一次打开时没有旧 API Key、旧会话或旧用户 Agent 预设。这不是数据丢失，而是新 `DSH_HOME` 正常隔离的证据。

## Profile 清单为什么这样写

`templates/tauri-profile/package.json` 使用：

```json
{
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",
        "@deepseek-ai/dsh-web-app"
      ]
    }
  }
}
```

这两个 bundle 来自 DSH 发行包。清单只是引用程序模块，不会复制 `web` profile，也不会复制任何用户状态。

## 数据是否共享

| 数据 | 同一 `DSH_HOME`、不同 profile | 不同 `DSH_HOME` |
| --- | --- | --- |
| API Key | 共享 | 隔离 |
| `settings.yaml` | 共享 | 隔离 |
| 会话 | 共享 | 隔离 |
| 用户 Agent 预设 | 共享 | 隔离 |
| profile bundle/patch | 隔离 | 隔离 |

更多设计细节见 [docs/architecture.md](docs/architecture.md)。

## 面向未来版本升级

对于可能包含破坏性变化的 DSH 新版本，不应让新旧二进制直接共享正式 `DSH_HOME`。推荐同时隔离 DSH 安装目录、`DSH_HOME` 和端口，将升级变成并行候选环境测试。

可以只把稳定环境的 profile 定义复制到新的候选 `DSH_HOME`：

```powershell
.\scripts\copy-profile-for-upgrade-test.ps1 `
  -SourceHome "D:\dsh\stable" `
  -TargetHome "D:\dsh\candidate-v2" `
  -Profile "tauri"
```

脚本不会复制 API Key、会话、设置、Agent 预设或旧 `node_modules`。目标 DSH 版本重新安装插件后，可在独立端口验证兼容性。兼容则提升候选版本；不兼容则停止候选进程并重新启动原 `DSH_HOME`，无需反向迁移或恢复备份。

完整理念、适用场景、兼容性判定和蓝绿升级流程见 [docs/version-isolation.md](docs/version-isolation.md)。

## 清理测试实例

先停止对应 DSH 进程，再明确检查路径，最后手动删除测试目录。不要把递归删除命令写成依赖未验证环境变量的脚本。

本仓库有意不提供自动删除工具，避免错误路径导致数据损失。

## License

MIT
