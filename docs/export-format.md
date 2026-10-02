# Memora export format

"Export all memories" in settings writes a zip you can keep, read with any
tool, or import somewhere else. Everything Memora holds about your images is
in it, apart from API keys, which never leave the device.

```
memora-export-2026-09-15.zip
├── manifest.json
├── memories.jsonl
├── conversations.jsonl
└── images/<memory-id>.<ext>
```

The format is versioned on its own, separate from the app version. A reader
should look at `format_version` first and stop if it is higher than the
version it knows. New optional fields can appear within the same version, so
ignore keys you don't recognize.

Current version: **1**.

## Conventions

- Files are UTF-8. The two `.jsonl` files hold one JSON object per line, with
  no wrapping array and no trailing commas.
- Timestamps are ISO 8601 in UTC, for example `2026-07-06T10:01:00.000Z`.
- Dates that came from image content, such as a due date, are calendar dates
  as `YYYY-MM-DD`. They carry no time zone because the image didn't give one.
- Keys with no value are left out rather than written as `null`.
- Money amounts appear twice: `value` is what the image showed, and
  `value_num` plus `currency` are the parsed form used for search.

## manifest.json

```json
{
  "format": "memora-export",
  "format_version": 1,
  "exported_at": "2026-09-15T04:30:00.000Z",
  "app_version": "0.1.0",
  "counts": { "memories": 128, "conversations": 6, "images": 128 }
}
```

| Field | Type | Meaning |
|-------|------|---------|
| `format` | string | Always `memora-export`. |
| `format_version` | number | The format this file follows. |
| `exported_at` | timestamp | When the export ran. |
| `app_version` | string | Version of Memora that wrote it. |
| `counts.memories` | number | Lines in `memories.jsonl`. |
| `counts.conversations` | number | Lines in `conversations.jsonl`. |
| `counts.images` | number | Files under `images/`. One per memory. |

## memories.jsonl

One line per memory, oldest taken first.

```json
{
  "id": "9f2c1f7a-2c2a-4b1f-9a41-7d1a0a5c9f3b",
  "image_file": "images/9f2c1f7a-2c2a-4b1f-9a41-7d1a0a5c9f3b.png",
  "source_path": "originals/9f2c1f7a-2c2a-4b1f-9a41-7d1a0a5c9f3b.png",
  "thumbnail_path": "thumbnails/9f2c1f7a.webp",
  "source": "gallery",
  "sha256": "3b0c…",
  "mime_type": "image/png",
  "width": 1080,
  "height": 2400,
  "byte_size": 421887,
  "taken_at": "2026-07-05T09:00:00.000Z",
  "added_at": "2026-07-06T10:00:00.000Z",
  "updated_at": "2026-07-06T10:01:00.000Z",
  "processed_at": "2026-07-06T10:01:00.000Z",
  "status": "ready",
  "attempts": 1,
  "summary": "Reliance electricity bill for July 2026",
  "category": "utility_bill",
  "visual_description": "A utility bill in a mobile app.",
  "extracted_text": "Reliance Energy\nAmount due Rs 1,690\n…",
  "entities": [
    { "type": "company", "value": "Reliance", "normalized_value": "reliance" }
  ],
  "attributes": [
    {
      "type": "amount",
      "value": "₹1,690",
      "value_num": 1690,
      "currency": "INR",
      "label": "total"
    },
    { "type": "due_date", "value": "31 Jul 2026", "value_date": "2026-07-31" }
  ],
  "keywords": ["reliance", "electricity", "bill"],
  "processing": [
    {
      "capability": "vision",
      "provider": "nvidia",
      "model": "meta/llama-3.2-11b-vision-instruct",
      "status": "succeeded",
      "latency_ms": 1840,
      "created_at": "2026-07-06T10:01:00.000Z"
    }
  ],
  "embeddings": [
    { "model_id": "local/bge-small-en-v1.5", "version": "ea104dacec62", "dimensions": 384 }
  ]
}
```

### The image

| Field | Type | Meaning |
|-------|------|---------|
| `id` | string | UUID v4. Used by references and result sets. |
| `image_file` | string | Where the original sits inside this zip. |
| `source_path` | string | Where it sat in app storage, relative to the app files directory. |
| `thumbnail_path` | string, optional | The generated thumbnail in app storage. Thumbnails are not exported, since they can be made again. |
| `source` | string | How the image arrived: `gallery`, `tile` or `share`. |
| `sha256` | string | Hash of the original bytes. Memora skips an import when this already exists. |
| `mime_type`, `width`, `height`, `byte_size` | | Facts about the original file. |
| `taken_at` | timestamp | When the image was taken. Memories are filed under this date. |
| `added_at` | timestamp | When it was added to Memora. |
| `updated_at` | timestamp | Last change to the row. |
| `processed_at` | timestamp, optional | When understanding finished. |
| `last_viewed_at` | timestamp, optional | Last time the detail screen was opened. |
| `status` | string | `captured`, `processing`, `ready`, `failed` or `reprocessing`. |
| `attempts` | number | How many times processing has been tried. |
| `failure_reason` | string, optional | Why the last attempt failed. |

### What a model understood

Every field below can be regenerated with "Reprocess", so a reader should
treat them as derived data rather than something the user typed.

| Field | Type | Meaning |
|-------|------|---------|
| `summary` | string, optional | One sentence naming what the image holds. |
| `category` | string, optional | Snake_case category such as `utility_bill`, `receipt`, `booking` or `chat`. Unknown values are kept as given, so this list can grow. |
| `visual_description` | string, optional | What kind of screen or scene this is. |
| `extracted_text` | string, optional | The readable text in reading order. |
| `entities[]` | array | Named things in the image. `type` is a word such as `company`, `person`, `location` or `product`. `value` is as shown, and `normalized_value` is lowercase with accents folded, which is what search matches on. |
| `attributes[]` | array | Typed facts. See below. |
| `keywords[]` | array | Lowercase search terms, at most 20. |

An attribute has:

| Field | Type | Meaning |
|-------|------|---------|
| `type` | string | What the fact is, for example `amount`, `due_date`, `invoice_number`, `booking_reference`, `phone`, `email` or `url`. |
| `value` | string | The display form, such as `₹1,690` or `31 Jul 2026`. |
| `value_num` | number, optional | The numeric form, for amounts and other numbers. |
| `value_date` | string, optional | `YYYY-MM-DD` for date attributes. |
| `currency` | string, optional | ISO 4217 code for amounts. |
| `label` | string, optional | Sub-type from the model, such as `total`, `subtotal` or `tax`. |

Account and card numbers are masked to their last four digits before they are
stored, so an export holds `•••• 4471` rather than the full number.

### Provenance

`processing[]` records each capability run for this memory, newest first.

| Field | Type | Meaning |
|-------|------|---------|
| `capability` | string | `vision`, `chat`, `embeddings` or `reranking`. |
| `provider` | string | Provider id, for example `nvidia`, `gemini` or `local`. |
| `model` | string | Model id as the user selected it. |
| `version` | string, optional | Model revision, when the provider reports one. |
| `status` | string | `succeeded` or `failed`. |
| `latency_ms` | number, optional | How long the call took. |
| `error` | string, optional | Why it failed. |
| `created_at` | timestamp | When it ran. |

`embeddings[]` describes the vectors Memora holds for this memory. The numbers
themselves are left out because they're large, they mean nothing without the
same model, and they can be rebuilt with "Reindex embeddings".

| Field | Type | Meaning |
|-------|------|---------|
| `model_id` | string | `<provider>/<model>`, for example `local/bge-small-en-v1.5`. |
| `version` | string | Model revision the vector was made with. |
| `dimensions` | number | Length of the vector. |

Only models the app knows about at export time are listed, which in practice
means the embedding model that is active.

## conversations.jsonl

One line per conversation, most recently updated first.

```json
{
  "id": "c8c0…",
  "title": "Bills",
  "created_at": "2026-09-14T00:00:00.000Z",
  "updated_at": "2026-09-14T12:00:05.000Z",
  "messages": [
    {
      "id": "m1",
      "role": "user",
      "content": "how much was the july bill?",
      "created_at": "2026-09-14T12:00:00.000Z"
    },
    {
      "id": "m2",
      "role": "assistant",
      "content": "It was ₹1,690.",
      "created_at": "2026-09-14T12:00:05.000Z",
      "provider": "groq",
      "model": "llama-3.3-70b-versatile",
      "presentation": {
        "layout": "strip",
        "headline": "₹1,690",
        "verification": "none",
        "search_only": false
      },
      "tool_trace": [
        {
          "tool": "search_by_entity",
          "arguments": { "value": "Reliance" },
          "summary": "1 candidate"
        }
      ],
      "references": [
        { "memory_id": "9f2c…", "position": 0, "relevance": 1.0 }
      ]
    }
  ],
  "active_result_set": {
    "id": "r1",
    "message_id": "m2",
    "description": "entity=Reliance",
    "memory_ids": ["9f2c…"],
    "created_at": "2026-09-14T12:00:00.000Z"
  }
}
```

| Field | Type | Meaning |
|-------|------|---------|
| `id`, `title` | string | The conversation. Titles come from the first question. |
| `created_at`, `updated_at` | timestamp | |
| `messages[]` | array | In the order they were sent. |
| `active_result_set` | object, optional | The memories the last search found, which follow-up questions worked on. |

A message has:

| Field | Type | Meaning |
|-------|------|---------|
| `id` | string | |
| `role` | string | `user` or `assistant`. |
| `content` | string | The text as shown. Citation markers have already been taken out and turned into `references`. |
| `created_at` | timestamp | |
| `provider`, `model` | string, optional | Which chat model answered. Missing when the answer came from search alone. |
| `presentation` | object, optional | How the sources were shown: `layout` (`strip` or `table`), `headline`, `headline_note`, `table_attribute`, `highlight_memory_id`, `source_label`, `verification` (`none`, `verified` or `corrected`) and `search_only`. |
| `tool_trace[]` | array, optional | What the agent did, with `tool`, `arguments` and a short `summary`. This is what "How this was found" shows. |
| `references[]` | array, optional | Memories the answer cited, with `memory_id`, `position` from 0, and `relevance` from 0 to 1 when it is known. |

References point at memory ids in `memories.jsonl`. A memory deleted after the
conversation happened is dropped from references, so every id you see resolves.

## images/

The original files, one per memory, named `<memory-id>.<ext>`. The extension
comes from the stored file, or from `mime_type` when the path has none. These
are byte-for-byte the files Memora imported. Memora never rewrites an
original, so a hash of the file still matches `sha256`.

Thumbnails are not included. They are generated from the originals and take up
space for no benefit here.

## Reading an export

A small reader can do something useful in a few lines. For example, to list
every bill over ₹2,000:

```python
import json

with open("memories.jsonl", encoding="utf-8") as lines:
    for line in lines:
        memory = json.loads(line)
        if memory.get("category") != "utility_bill":
            continue
        for attribute in memory["attributes"]:
            if attribute["type"] == "amount" and attribute.get("value_num", 0) > 2000:
                print(memory["taken_at"], attribute["value"], memory["summary"])
```

## What is not in an export

- API keys and any other secret. They live in the Android Keystore and are
  never written to the database or to an export.
- Embedding vectors. Their metadata is exported so you can see what would need
  rebuilding.
- Thumbnails, the full-text search index and other caches. All of them are
  derived from what is here.
