# AI 验证说明

本项目通过 Moonshot 的 OpenAI 兼容 Chat Completions API，让 `AIManager` 直接连接 Kimi。

## 环境配置

启动 Godot 前，可以先设置系统环境变量：

```powershell
$env:MOONSHOT_API_KEY="你的真实 API Key"
$env:MOONSHOT_BASE_URL="https://api.moonshot.cn/v1"
$env:MOONSHOT_MODEL="kimi-k2.6"
```

也可以在项目根目录创建本地 `.env` 文件。如果 `.env` 不存在，`AIManager` 也会读取名为 `env` 的文件。

```env
MOONSHOT_API_KEY=你的真实 API Key
MOONSHOT_BASE_URL=https://api.moonshot.cn/v1
MOONSHOT_MODEL=kimi-k2.6
```

不要提交真实 API Key。

## 手动验证流程

1. 使用 Godot 4.6.2 打开项目。
2. 启动游戏并点击“New Game”。
3. 确认第一次 AI 响应会通过 `commands` 驱动场景。
4. 临时清空 `MOONSHOT_API_KEY` 后再次启动。
5. 确认游戏会显示兜底对话，而不是崩溃或卡死。

## 静态检查

以后提交 AI 相关改动前，建议运行：

```powershell
git diff -- scripts/managers/script_engine.gd scripts/managers/dialogue_manager.gd
Select-String -Path env.example -Pattern "your_api_key_here"
Select-String -Path scripts/managers/ai_manager.gd -Pattern "CharacterManager|BackgroundManager|AudioManager|ParticleManager|CGManager|UIManager|GameManager"
```

如果 Godot 已加入 `PATH`，也可以运行当前 Godot 版本对应的无头导入或脚本检查命令。
