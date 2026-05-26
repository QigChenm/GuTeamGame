# AI Verification

This project connects `AIManager` directly to Kimi through the Moonshot OpenAI-compatible chat completions API.

## Environment

Set these variables before launching Godot:

```powershell
$env:MOONSHOT_API_KEY="your_real_api_key"
$env:MOONSHOT_BASE_URL="https://api.moonshot.cn/v1"
$env:MOONSHOT_MODEL="kimi-k2.6"
```

Do not commit real API keys.

## Manual Flow

1. Open the project with Godot 4.6.2.
2. Start the game and click "New Game".
3. Confirm the first AI response drives the scene through `commands`.
4. Temporarily unset `MOONSHOT_API_KEY` and start again.
5. Confirm the game shows the fallback dialogue instead of crashing or freezing.

## Static Checks

Run these before committing future AI changes:

```powershell
git diff -- scripts/managers/script_engine.gd scripts/managers/dialogue_manager.gd
Select-String -Path env.example -Pattern "your_api_key_here"
Select-String -Path scripts/managers/ai_manager.gd -Pattern "CharacterManager|BackgroundManager|AudioManager|ParticleManager|CGManager|UIManager|GameManager"
```

If Godot is available in `PATH`, also run the project's normal headless import or script check command for the installed Godot version.
