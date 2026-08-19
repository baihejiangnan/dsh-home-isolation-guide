# DSH 版本隔离、插件兼容性测试与零成本回退

## 为什么版本隔离值得做

`DSH_HOME` 隔离不仅适合首次安装，也适合应对 DSH 未来可能出现的破坏性变化。新版本可能改变：

- `settings.yaml` 的结构或默认值；
- 会话、索引和 `storages/` 的持久化格式；
- profile manifest、bundle composition 或 patch 语义；
- 插件 API、服务接口、事件和注入点；
- Agent 预设、工具权限及沙箱行为；
- 内置 bundle 的模块集合与加载顺序。

如果新旧 DSH 二进制直接共用一个 `DSH_HOME`，新版可能对状态执行单向迁移。即使新版运行正常，旧版也未必还能读取迁移后的数据。因此，“升级后二进制可以回滚”并不等于“状态可以回滚”。

版本隔离把升级从原地修改变成并行部署：

```text
稳定环境                              候选环境
DSH binary v1                         DSH binary v2
DSH_HOME=D:\dsh\stable                DSH_HOME=D:\dsh\candidate
port=3081                             port=3082
```

稳定环境在整个测试期间保持不变。候选环境失败时，只需停止候选进程并重新打开稳定环境，不需要执行数据库降级、配置回滚或文件恢复。

## 推荐使用场景

- 稳定版升级到新的 major、RC 或 nightly。
- DSH 发布说明包含数据迁移、profile 或插件 API 变化。
- 桌面应用准备更新其捆绑 DSH 版本。
- 维护私有插件、GitHub 插件或 profile patch。
- 需要同时比较新旧版本行为、性能或输出质量。
- 生产环境要求快速回退和明确的变更窗口。
- CI 需要在干净状态中验证安装及首次启动。

普通个人用户的小版本升级不一定需要永久保留多个实例，但在无法确认状态格式兼容时，至少应使用一次临时候选 `DSH_HOME`。

## 三个必须一起隔离的维度

完整实例由三个地址组成：

1. **DSH 安装路径**：决定实际执行哪个版本，以及内置 bundle 的版本。
2. **`DSH_HOME`**：决定凭据、会话、设置、用户预设、存储和 profile 的位置。
3. **监听端口**：允许新旧实例并行运行，避免端口冲突。

只改变其中一个并不完整。例如只换 `DSH_HOME` 仍然运行同一个 DSH 版本；只换二进制但共用 `DSH_HOME` 仍可能触发破坏性状态迁移。

## 复制 profile，而不是复制整个 DSH_HOME

插件兼容性测试需要保留“装了哪些插件、使用哪些版本、有哪些 profile patch”，但不应把旧会话、API Key 和用户状态带入候选环境。因此应复制：

```text
profiles/<name>/package.json
profiles/<name>/cordis.patch.yml
profiles/<name>/pnpm-lock.yaml       # 如果存在，用于固定第三方插件版本
profiles/<name>/其他插件配置文件
```

不应复制：

```text
.credentials.yaml
settings.yaml
sessions/
.agent-presets/
storages/
profiles/<name>/node_modules/
```

尤其不要复制 `node_modules`。候选环境应由目标 DSH 版本重新安装第三方插件，这样才能发现依赖、peer dependency、原生模块以及运行时 API 的真实兼容问题。DSH 的内置 `dsh-base`、`dsh-web-app` 等 bundle 由目标安装目录解析，不需要复制。

## 可复现的升级测试流程

假设当前稳定环境为 `D:\dsh\stable`，候选环境为 `D:\dsh\candidate-v2`，profile 为 `tauri`。

### 1. 克隆可移植 profile 定义

```powershell
.\scripts\copy-profile-for-upgrade-test.ps1 `
  -SourceHome "D:\dsh\stable" `
  -TargetHome "D:\dsh\candidate-v2" `
  -Profile "tauri"
```

脚本要求目标目录不存在，只复制 profile 下的文件并排除所有 `node_modules`。它不会读取或复制 API Key、会话、设置和 Agent 预设。

### 2. 用目标版本重新安装 profile 插件

将环境变量只设置给当前测试终端，然后调用目标版本的 DSH：

```powershell
$env:DSH_HOME = "D:\dsh\candidate-v2"

& "D:\dsh-bin\v2\dsh.cmd" plugin --profile tauri install
```

如果 DSH 是 Node.js 入口：

```powershell
$env:DSH_HOME = "D:\dsh\candidate-v2"

& "D:\dsh-bin\v2\node.exe" `
  "D:\dsh-bin\v2\node_modules\@deepseek-ai\dsh\lib\bin.js" `
  plugin --profile tauri install
```

### 3. 先做静态组合检查

```powershell
$env:DSH_HOME = "D:\dsh\candidate-v2"

& "D:\dsh-bin\v2\dsh.cmd" `
  --profile tauri `
  --dump-default-config
```

这一步可以提前暴露 bundle 缺失、manifest 无效、patch 目标变化和模块解析失败。

### 4. 使用独立端口启动候选版本

```powershell
$env:DSH_HOME = "D:\dsh\candidate-v2"

& "D:\dsh-bin\v2\dsh.cmd" `
  --profile tauri `
  --host 127.0.0.1 `
  --port 3082
```

稳定版本继续使用原 `DSH_HOME` 和 `3081`。候选版本不要连接生产 API Key；应使用专门的测试凭据，或只验证不需要外部调用的功能。

## 插件兼容性的判定标准

“能够启动”只是最低标准。建议至少验证：

- profile 可组合且启动日志没有未解析模块或 patch 警告；
- 插件能被列出、加载和卸载；
- 插件注册的页面、命令、工具、事件和服务可以调用；
- 新建会话、重启进程后状态仍一致；
- 插件写入的数据能被候选版本再次读取；
- Windows 原生模块、终端、沙箱和子进程功能正常；
- 插件安装、升级、取消和删除流程正常；
- 目标版本的健康检查和关键自动化测试通过。

对于保存重要数据的插件，还应使用合成测试数据验证其迁移路径，而不是复制真实生产数据。

## 兼容时如何升级

测试通过后有两种策略：

### 保留通道目录

```text
D:\dsh\stable
D:\dsh\beta
D:\dsh\dev
```

将候选版本提升为 stable 时更新启动器指针或应用配置。优点是路径稳定、运维简单，适合桌面应用。

### 保留精确版本目录

```text
D:\dsh\v1.8.0
D:\dsh\v2.0.0
```

通过 `current` 配置记录当前版本。优点是审计和复现准确，适合 CI、企业部署及插件开发。

不要在未经验证的情况下把候选 `DSH_HOME` 覆盖到稳定目录。若要迁移真实会话或设置，应使用 DSH 官方迁移机制；没有官方机制时，保留旧环境并将迁移视为单独项目。

## 不兼容时如何零成本切换

所谓“零成本回退”是指稳定状态从未被候选版本写入。回退动作只有：

1. 停止候选 DSH 进程。
2. 启动原 DSH 二进制。
3. 注入原来的稳定 `DSH_HOME`。
4. 使用原来的稳定端口或恢复路由指针。

```powershell
$env:DSH_HOME = "D:\dsh\stable"
& "D:\dsh-bin\v1\dsh.cmd" --profile tauri --host 127.0.0.1 --port 3081
```

不需要反向迁移、恢复备份或撤销插件安装。候选目录可以保留用于诊断，也可以在确认路径和进程均正确后由管理员清理。

## 自动化发布建议

桌面应用或部署系统可以维护一份实例注册表：

```json
{
  "stable": {
    "version": "1.8.0",
    "binary": "D:/dsh-bin/v1.8.0/dsh.cmd",
    "home": "D:/dsh/stable",
    "port": 3081
  },
  "candidate": {
    "version": "2.0.0-rc.1",
    "binary": "D:/dsh-bin/v2.0.0-rc.1/dsh.cmd",
    "home": "D:/dsh/candidate-v2",
    "port": 3082
  }
}
```

发布流水线依次执行：创建候选目录、复制 profile 定义、安装插件、dump config、启动、健康检查、端到端测试。只有全部通过才更新 stable 指针。失败时保持 stable 指针不变。

这是一种蓝绿部署思路：`DSH_HOME` 是状态颜色，DSH 安装目录是程序颜色，端口或启动器指针负责流量切换。
