# Changelog

All notable changes to Memora are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
