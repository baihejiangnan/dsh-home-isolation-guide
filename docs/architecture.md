# DSH 状态隔离原理

## 两个容易混淆的边界

`DSH_HOME` 是状态根目录，profile 是其中的一套程序组成。换 profile 只改变加载哪些 bundle 和 patch；换 `DSH_HOME` 才会隔离凭据、会话、设置和用户预设。

```text
DSH_HOME
|-- .credentials.yaml       # API Key 等托管凭据
|-- settings.yaml           # Provider、模型和界面设置
|-- sessions/               # 会话记录
|-- .agent-presets/         # 用户创建的 Agent 预设
|-- storages/               # Web 客户端及插件存储
`-- profiles/
    `-- tauri/
        |-- package.json    # bundle 顺序和第三方插件依赖
        `-- cordis.patch.yml
```

同一 `DSH_HOME` 下的 `web` 和 `tauri` profile 会共享上层状态。不同 `DSH_HOME` 即使都叫 `tauri`，也不会共享这些文件。

## Bundle 不是用户数据

示例 profile 引用两个发行包自带的 bundle：

- `@deepseek-ai/dsh-base`：核心服务和 Agent 能力。
- `@deepseek-ai/dsh-web-app`：网页服务、前端和桌面嵌入所需能力。

这只是模块引用，不复制旧 profile，也不包含 API Key、会话或用户预设。DSH 优先从自己的安装目录解析内置 bundle，然后才从 profile 的 `node_modules` 解析第三方插件。

## 进程级环境变量

推荐只对子进程设置 `DSH_HOME`：

```text
Desktop process
`-- DSH child process
    |-- DSH_HOME=D:\instances\desktop-a
    `-- --profile tauri
```

不要用系统级环境变量保存某个实例的路径，否则从其他终端启动的 DSH 也可能意外进入同一个状态根目录。

## 如何保证“全新”

创建器必须满足以下不变量：

1. 将输入转换成绝对路径。
2. 目标目录已存在时拒绝运行，而不是合并内容。
3. 只写最小 profile 清单和合法的空 patch `[]`。
4. 不读取 `~/.dsh`，不复制其他 profile。
5. 启动子进程时显式注入新目录。

如果需要重复启动同一个实例，应把“初始化”和“启动已有实例”设计成两个不同命令。仓库中的创建示例刻意拒绝已有目录，以免演示代码静默复用旧状态。

## 安全注意事项

- 不要提交 `.credentials.yaml`、`.env`、会话或日志。
- API Key 应通过 DSH 凭据界面写入新实例，或在启动环境中提供。
- 一个新的 `DSH_HOME` 不会继承旧 API Key，这是隔离正常生效的表现。
- 文件隔离不是操作系统账户隔离。同一 Windows 用户运行的进程通常仍有权限主动读取该用户可访问的其他路径。
