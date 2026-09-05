# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## 项目概述

将 SearXNG（开源元搜索引擎）移植到原生 Windows 环境的项目，无需 WSL 或 Docker，通过随附的嵌入式 Python 3.11.9 直接运行。源码位于 `python/Lib/site-packages/searx/`，是**上游同步 + 本地修改版**，非独立工程。

上游同步历史（来自 `README.md` 与 `python/Lib/site-packages/searx/version_frozen.py`）：

| 日期 | 上游基线 |
|------|---------|
| 2026.8.19（当前） | commit `374939b888c8644b408b793fe42d584454631cec` |
| 20250513 | commit `5d99373bc65c7087ee743a1fe44897bad6065338` |
| 20250424 | SearXNG 2025.4.25+9ec9499d8，首次做 Windows 适配 |

注意 `version_frozen.py` 中的 `GIT_URL` 指向 `github.com/mbaozi/SearXNGforWindows`，而上游 `version.py` 的回退值是 `"unknown"` —— 这个冻结文件是本地定制的（上游把它 gitignore，本仓库则纳入跟踪）。

## 启动与运行

服务监听 `127.0.0.1:8888`。

| 方式 | 说明 |
|------|------|
| `.vbs` | 无窗口后台启动（`pythonw.exe`），若服务已在运行则仅打开浏览器 |
| `.bat` | 前台启动，保留终端日志，约 5 秒后打开浏览器 |
| `Stop SearXNG.bat` | `netstat -ano` 按端口 8888 找 PID 后 `taskkill /F` |

手动启动：
```
.\python\python.exe .\python\Lib\site-packages\searx\webapp.py
```

> **必须从仓库根目录启动。** 配置路径由 `os.getcwd()` 拼接，在其他目录执行会找不到配置。`.vbs` 的 `shell.CurrentDirectory = appDir`、`.bat` 的 `cd /d "%~dp0"` 就是为此存在。
>
> **`Stop SearXNG.bat` 把端口 8888 写死了**，改用其他端口后需手动 `taskkill`。

## 相对上游的实际改动（同步时最关键）

`searx/` 中只有 3 个 `.py` 文件偏离上游，已逐个核对：

| 文件 | 改动内容 |
|------|---------|
| `settings_loader.py:36` | `DEFAULT_SETTINGS_FILE` 从 `os.getcwd()/config/` 加载（上游是 `os.getcwd()/searx/`） |
| `limiter.py:142,237` | `limiter.toml` 同样改从 `os.getcwd()/config/` 加载；`:237` 在早退判断前挂载入口限流钩子 `rate_limit.install(app)` |
| `valkeydb.py:22,65` | 移除 `pwd` 导入（Windows 无此模块），`os.getuid()` 改为 `os.getpid()` |

**同步上游时这三处必须重新打补丁。** 验证补丁完整性的方法：`grep -rn '"config"' python/Lib/site-packages/searx --include="*.py"` 应恰好返回上面前两行，不多不少。

`valkeydb.py` 的补丁保留了变量名 `_pw_uid`（实际存的是 PID），是本地补丁遗留。该分支只在 valkey 连接失败时执行，而 `valkey.url: false`，正常运行不会触发。

**代码里没有任何平台适配分支**：`searx/` 中不存在 `sys.platform`、`os.name`、`WindowsSelectorEventLoopPolicy`、`signal.signal`。Windows 兼容性几乎完全靠「配置路径从 `searx/` 改到 `config/`」+「去掉 `pwd`」+ 嵌入式 Python 打包这三件事实现；进程生命周期交给外部脚本，代码内没有信号处理。`webapp.py` 是上游原样代码。

`searx/rate_limit.py` 是**新增文件，不是偏离文件**：它对 `/search` 做入口限流，`rate_limit.per_minute`（默认 10）是 60s 滑动窗口、超出返回 HTTP 429 并带 `Retry-After`，`rate_limit.min_interval`（默认 0.5）是最短间隔、间隔不足则**排队等待**而非拒绝，所以 OpenClaw 不会丢请求。两个键写在 `config/settings.yml` 的独立顶层 `rate_limit:` 段，由 `get_setting` 点路径查找读取，**不需要**改 `settings_defaults.py`。钩子挂在 `limiter.py:237`，必须位于该函数 `server.limiter` 早退判断**之前**，否则 `limiter: false` 时 `before_request` 注册不上。新文件不会被上游同步覆盖，所以偏离文件仍是上面 3 个；429 由 `before_request` 返回 Response 短路，`webapp.py` 未受影响。`per_minute` 设 0 可整体关闭配额。

> 本机无法与上游 diff（网络受限、无 git 历史）。`settings_defaults.py:233-234` 的 `.replace("\\", "/")` **可能是上游代码**，不要当作本仓库改动去回退。

## 嵌入式 Python 环境（勿随意改动）

- **`python/python311._pth` 中的 `import site` 必须保持取消注释。** 嵌入式 Python 发行版默认把这行注释掉；它是 `Lib/site-packages` 能被导入的唯一原因，一旦被覆盖回注释状态，服务完全无法启动。
- 全部标准库打包在 `python311.zip`（649 项）中，`python/Lib/` 下只有 `site-packages`。
- **`searx` 是复制进去的，不是 pip 安装的**（`site-packages/` 中没有 `searx.dist-info` 或 `searx.egg-info`）。`pip install` 不会更新它。
- `searx/version_frozen.py` 是本仓库自持的冻结版本文件，本仓库没有 git 历史，`version.py` 中的 git 子进程探测会失败。它的存在让 `version.py` 短路、不再 spawn git。
- `config/requirements.txt` 的 20 个包已在嵌入式 Python 中装好。改依赖要**同时**更新清单和 `python/Lib/site-packages/`（用 `python/Scripts/pip.exe`），否则清单与运行环境脱节。

## 配置加载机制（与上游文档不同）

`settings_loader.py` 被本地改过：

```python
DEFAULT_SETTINGS_FILE = os.path.join(os.getcwd(), "config", SETTINGS_YAML)
```

后果有四点，均与 `docs.searxng.org` 的描述不符：

1. **`config/settings.yml` 是唯一被加载的配置。** `python/Lib/site-packages/searx/settings.yml` 运行时从不被读取 —— 它是上游原样文件（`instance_name: "SearXNG"`、`secret_key: "ultrasecretkey"`），磁盘上仍保留，但属死文件。**不要改动它，也不要期望改它生效**；若误被加载，`webapp.py` 会因 `secret_key == 'ultrasecretkey'` 直接 `sys.exit(1)`。
2. **`config/settings.yml` 必须是完整配置。** Windows 上 `get_user_cfg_folder()` 返回 `None`，`load_settings()` 提前返回，`update_settings()` 的整套合并逻辑是死代码 —— 写 `use_default_settings: true` 做增量覆盖不会生效。新增或修改配置项要写全量。
3. 该文件缺失时 `load_yaml()` 抛 `SearxSettingsException`，服务直接起不来。
4. 文件内 docstring 仍写着「default settings from `searx/settings.yml`」，是遗留注释，与实际行为不符。

默认启用（`disabled: false`）的引擎共七个：百度、Bing、Bing 新闻、夸克、搜狗、搜狗微信、yahoo，其余全部 `disabled: true`（Bing 图片/视频、搜狗图片/视频、SoundCloud、yahoo news 均已禁用）。`README.md` 中「仅保留搜狗和百度」的说法已过期。

**yahoo 是唯一走代理的引擎。** 这是本仓库唯一的代理定制，纯配置、无代码改动：`outgoing.networks.yahoo.proxies: socks5h://127.0.0.1:10808` + yahoo 引擎条目上的 `network: yahoo`。没有 `network` 键的引擎走直连默认路径，全局 `outgoing.proxies` 保持 `None`。三处必须配套，改一处要一起改：

1. `outgoing.networks.yahoo` 里必须 `enable_http2: false`。SOCKS5 隧道会把 HTTP/2 的 TLS 记录层打坏（`ssl.SSLError: DECRYPTION_FAILED_OR_BAD_RECORD_MAC`，异常从 `httpcore/_async/http2.py` 抛出），表现为结果页 `unexpected crash`。
2. yahoo 条目必须有 `timeout: 10`。全局 `request_timeout: 3.0` 小于代理链路的实际耗时（约 4-5s），否则报 `timeout`。
3. 用 `socks5h://`（代理端解析域名），不是 `socks5://`（本地解析），避免被污染的 DNS。

代理能力来自 `httpx_socks` 0.13.1 + `python_socks`（**不是 `requests` + PySocks**，本项目已迁移到 httpx 0.28.1，环境里没有 requests）。SOCKS 传输的构造在 `network/client.py:114` 与 `network/client.py:184`，`socks5h://` 会在内部改写为 `socks5://` 并置 `rdns=True`。

结果页里的 `web.archive.org` 链接是 `ui.cache_url`（`settings_defaults.py:243`）给**所有**引擎生成的「缓存」链接，与代理无关，不要据此判断某引擎是否走了代理。

`config/limiter.toml` 与 `searx/limiter.toml` 逐字节相同，前者是运行时实际读取的那份。

## 环境变量

覆盖机制是 `settings_defaults.py` 中声明式的 `SettingsValue(..., environ_name='SEARXNG_PORT')`，运行时查 `os.environ`。**改默认值要改 `settings_defaults.py`，不是 `searx/settings.yml`。**

实际生效的变量（以 `settings_defaults.py` 为准）：

`SEARXNG_BASE_URL`、`SEARXNG_BIND_ADDRESS`、`SEARXNG_DEBUG`、`SEARXNG_DEBUG_LOG_LEVEL`、`SEARXNG_DISABLE_ETC_SETTINGS`、`SEARXNG_IMAGE_PROXY`、`SEARXNG_LIMITER`、`SEARXNG_METHOD`、`SEARXNG_MSG_FILE`、`SEARXNG_ORG`、`SEARXNG_PORT`、`SEARXNG_PUBLIC_INSTANCE`、`SEARXNG_REDIS_URL`、`SEARXNG_SECRET`、`SEARXNG_SETTINGS_PATH`、`SEARXNG_VALKEY_URL`

## 无测试与构建套件

仓库中没有测试设施：不存在 `searx/test`、`pyproject.toml`、`setup.cfg`、`pytest.ini`、`tox.ini`、`Makefile`，`python/Scripts/` 中也没有 pytest。因此**没有可运行的测试命令**，改动后的验证方式是实际启动服务并访问 `http://127.0.0.1:8888`。

若要引入上游测试，注意上游测试假设 cwd 是 git checkout 且 `searx/` 在根目录 —— 这正是本移植在 `settings_loader.py:36` 和 `limiter.py:142` 打破的假设。

## 关键注意事项

- **`.pyd` 是合法文件**，是 Python C 扩展 DLL，必须保留跟踪；`.gitignore` 排除的是 `.pyc`、`__pycache__/`、`*.log`、`*.db`、`*.sqlite*`、`instance/`、`.searxngrc`、`searxng.settings.yml`。
- **隐私数据不要提交**：被忽略的 `*.log`、`*.db`、`*.sqlite*`、`instance/` 含运行时查询记录与搜索缓存，`.searxngrc` / `searxng.settings.yml` 是本地用户配置。
- **无 valkey 缓存**：`settings.yml` 中 `valkey.url: false`，不依赖外部 Redis/Valkey。
- **limiter 默认关闭**：`server.limiter: false`；`config/limiter.toml` 仅在启用时生效。
- `webapp.py` 文件末尾按序执行 `ProxyFix` → `WhiteNoise` → `patch_application` → `init()`，且 `init()` 在**导入时**即执行，不是等到 `run()`。
- `searx/` 下的 `.py` 文件注释均为英文，改动时保持一致。
- 本仓库维护两份镜像文档：`CLAUDE.md`（Claude Code）与 `AGENTS.md`（Codex），内容除首行外完全一致，修改时需同步更新。
