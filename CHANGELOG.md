# Changelog

All notable changes to Memora are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0]

### Added

- **A model that runs on your phone.** Settings can import a Gemma model file and use it for Ask and for reading images, so a device-only setup answers questions in sentences instead of listing search results. The section lists Gemma 3 1B and Gemma 3n E2B with their size, what each one adds and whether this phone has the memory for it, and it says plainly when the phone does not, rather than letting a three gigabyte download fail at the end. The file comes from the model's own page, because the licence is accepted there before the download link appears. Nothing leaves the phone, answers come more slowly than from a cloud model, and it uses battery while it works.
- Importing a model shows how far the copy has got. A model file runs to three gigabytes and the copy takes minutes, so the bar moves instead of looking stuck. A source that will not say how large the file is gets a bar with no end rather than a wrong one.
- A small model does not always manage a tool call. When it cannot, Ask answers from search instead of from something the model made up, and the answer still names the model it tried.

### Changed

- The APK is about 25 MB larger on arm64, because the generative runtime ships with the app rather than being downloaded later. That cost lands on everyone, including people who never import a model, and it was accepted because running AI on your own phone is what Memora is for.
- Local-only mode no longer says chat is unavailable. With a model imported and selected, it names the model answering on the phone.

## [0.1.1]

### Added

- **An app icon.** The Memora mark, a stack of saved images with a spark on the front one. It ships as an adaptive icon, as a monochrome version so themed icons work on Android 13 and newer, and as the Quick Settings tile.
- **A conversation drawer in Ask.** The history button opens a drawer down the left edge listing your conversations, pinned ones first, each with when it was last used and the open one marked. Every row can be pinned, renamed or deleted. Deleting the conversation you are in starts a fresh one.

### Changed

- **Adding images says when nothing will be understood.** With no vision model selected, a key the provider rejected, a provider that cannot run the chosen model, or one that is rate limiting, the toast after an add names the reason and links to the screen that settles it, instead of leaving the images in a queue that cannot move. The queue banner says the same thing and covers every reason the queue reports, including a rate limit it is waiting out and the time it picks up again.

### Fixed

- Keywords on a memory took a whole line each. They now sit beside each other as chips and wrap onto as many lines as they need, the way the design draws them.

## [0.1.0]

The first release. Memora turns images you choose to keep into a private, searchable memory you can ask questions about.

### Added

- **Adding images.** Pick any number from your gallery, share images to Memora, or save the screen with a Quick Settings tile. The tile uses an opt-in accessibility service when you enable it, and the system capture prompt otherwise. Images are filed under the date each one was taken and are browsable immediately.
- **A queue you can see.** Images are understood one at a time in the background, overnight while charging by default, with pause, retry and a process-now option. Adding never waits on AI.
- **Understanding.** A vision model produces a summary, a category, visible text, entities, amounts, dates and identifiers, normalized into typed facts.
- **Search that combines three strategies.** Structured filters for questions like "over 2000 last year", full-text search over what an image said, and vector search for what it meant, fused and reranked.
- **Ask.** A conversation over your memories, answered through typed read-only tools, showing the memories behind each answer and the searches that found them. A single figure can be checked against the original image. Ask still works with no chat model configured, answering from search and local aggregation.
- **Your choice of AI.** Vision, chat, embeddings and reranking are chosen independently across OpenAI, Groq, NVIDIA, OpenRouter, Gemini, Anthropic, any OpenAI-compatible endpoint, a model you run yourself through Ollama or LM Studio, or on-device. API keys are encrypted under an Android Keystore key.
- **Local-only mode** that refuses every request to a public host, with on-device text recognition and on-device semantic search.
- **Your data.** Export everything as a documented zip, and delete one memory or the whole library for good.
- Dark and light themes. Android 8.0 and newer.

### Known limitations

- On-device reranking uses score fusion rather than a cross-encoder model.
- There is no on-device chat model. Local-only mode answers with search instead.
- The export format is version 1 and has no importer yet.
