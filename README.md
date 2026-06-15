# MacTranslateLens

Local-first screen translation for macOS.

MacTranslateLens is a small menu-bar app that lets you select a region on screen, extracts text locally with Apple Vision OCR, sends it to a local Ollama-compatible model endpoint, and shows the Hebrew translation in a floating window.

## Current MVP

- Menu-bar app
- **Global shortcut to translate clipboard text** (default `⌃⌥⌘T`) — needs no permission
- Translate selected screen region (optional; requires Screen Recording)
- Local OCR through Apple's Vision framework
- Local model call through an Ollama-compatible `/api/generate` endpoint
- No cloud API keys

## Everyday use: the global shortcut

The fastest workflow needs no permissions at all:

1. Select text anywhere and copy it (`⌘C`).
2. Press the global shortcut **`⌃⌥⌘T`**.
3. The Hebrew translation pops up in a floating window.

To change the shortcut, set the `hotkey` default (or the
`MAC_TRANSLATE_LENS_HOTKEY` env var) to a combo like `cmd+shift+t`:

```sh
defaults write com.gadshushan.MacTranslateLens hotkey "cmd+shift+t"
```

Accepted tokens: `cmd`/`shift`/`opt`/`ctrl` plus one key (`a`–`z`, `0`–`9`, or
`space`). The shortcut is registered with the Carbon Hot Key API, so it works
system-wide without Accessibility or Input Monitoring permission.

## Requirements

- macOS 14+
- Apple Silicon recommended
- A local model server, for example Ollama or LM Studio
- Screen Recording permission for region capture

## Run the local translation model

The default and recommended model is **`aya-expanse:8b`** — Cohere's multilingual
model (Hebrew officially supported). It gives excellent Hebrew (days, dates and
numbers stay correct), uses ~5.5 GB of RAM, and translates in ~1.5 s once warm.

Install Ollama, then pull the model:

```sh
ollama pull aya-expanse:8b
ollama serve
```

The app keeps the model warm and **preloads it on launch** (`keep_alive` 30 min),
so translations stay near-instant during a session while the model frees its RAM
when idle. It also sends a tuned system prompt and inference options (low
temperature, anti-transliteration, OCR-noise cleanup), so quality does not depend
on a custom Modelfile — any capable multilingual model works.

If your model name is different, launch MacTranslateLens with:

```sh
MAC_TRANSLATE_LENS_MODEL="your-model-name" .build/debug/MacTranslateLens
```

For the `.app` bundle, configure the model with macOS defaults:

```sh
defaults write com.gadshushan.MacTranslateLens model "aya-expanse:8b"
defaults write com.gadshushan.MacTranslateLens endpoint "http://127.0.0.1:11434/api/generate"
```

### Alternatives

Set any of these via the `model` default above. Note: on 18 GB you trade quality
against memory — pick by what you run alongside it.

- **`gemma3:4b`** — lightest (~3.6 GB) and fastest (~1.6 s); safe to pin
  permanently, but occasionally mistranslates days of the week.
- **`mac-translate-hebrew-12b`** (DictaLM 3.0 Nemotron 12B) — top Hebrew quality,
  but ~7.8 GB RAM bogs down an 18 GB Mac. Pull with:
  `ollama pull hf.co/dicta-il/DictaLM-3.0-Nemotron-12B-Instruct-GGUF:Q4_K_M`
  then `ollama cp … mac-translate-hebrew-12b`.
- **`gemma4:e4b`** — Google Gemma 4; excellent quality but ~7.5 GB RAM at runtime
  (the "Effective 4B" name is misleading) and a slow ~25 s cold load.

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

The clipboard shortcut (`⌃⌥⌘T`) needs **no permissions**.

Only the optional **Translate Screen Region** feature requires Screen Recording.
You are asked for it the first time you use that feature — not on launch:

System Settings → Privacy & Security → Screen Recording → MacTranslateLens

After granting permission, quit and reopen the app. Note: an unsigned/ad-hoc
build changes identity on each rebuild, so macOS re-asks after every rebuild.
A stable Developer ID signature avoids this.

## Roadmap

- Better multi-display capture
- Translation target language picker
- Direct selected-text capture through Accessibility
- Replace selected text with translated text
- Native MLX worker instead of an external local server
