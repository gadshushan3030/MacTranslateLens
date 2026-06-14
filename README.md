# MacTranslateLens

Local-first screen translation for macOS.

MacTranslateLens is a small menu-bar app that lets you select a region on screen, extracts text locally with Apple Vision OCR, sends it to a local Ollama-compatible model endpoint, and shows the Hebrew translation in a floating window.

## Current MVP

- Menu-bar app
- Translate selected screen region
- Translate clipboard text
- Local OCR through Apple's Vision framework
- Local model call through an Ollama-compatible `/api/generate` endpoint
- No cloud API keys

## Requirements

- macOS 14+
- Apple Silicon recommended
- A local model server, for example Ollama or LM Studio
- Screen Recording permission for region capture

## Run a local Gemma model

Install Ollama, then pull a Gemma model that exists in your local setup. Example:

```sh
ollama pull gemma4:e4b
ollama serve
```

If your model name is different, launch MacTranslateLens with:

```sh
MAC_TRANSLATE_LENS_MODEL="your-model-name" .build/debug/MacTranslateLens
```

For the `.app` bundle, configure the model with macOS defaults:

```sh
defaults write com.gadshushan.MacTranslateLens model "your-model-name"
defaults write com.gadshushan.MacTranslateLens endpoint "http://127.0.0.1:11434/api/generate"
```

You can also override the endpoint:

```sh
MAC_TRANSLATE_LENS_ENDPOINT="http://127.0.0.1:11434/api/generate" .build/debug/MacTranslateLens
```

## Build and run

```sh
swift build
.build/debug/MacTranslateLens
```

To build a minimal `.app` bundle:

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open .build/MacTranslateLens.app
```

To build an installable `.dmg`:

```sh
chmod +x scripts/package-dmg.sh
./scripts/package-dmg.sh
open dist/MacTranslateLens.dmg
```

Then drag `MacTranslateLens.app` into `Applications`.

## First-run permissions

For screen-region translation, grant Screen Recording permission:

System Settings → Privacy & Security → Screen Recording → MacTranslateLens

After granting permission, quit and reopen the app.

## Roadmap

- Global hotkey
- Better multi-display capture
- Translation target language picker
- Direct selected-text capture through Accessibility
- Replace selected text with translated text
- Native MLX worker instead of an external local server
