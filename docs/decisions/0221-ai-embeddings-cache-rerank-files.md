# 0221: Cache embeddings, rerank hits and upload files to the provider

- Status: accepted
- Date: 2026-11-03

## Context

Embedding the same text twice costs money, hits come back unranked, and files that an app already stores are sent again as bytes on every call.

## Decision

- `embeddingCacheMiddleware` caches per model and `dimensions`; `rerankHits` and the search `Embedder` take `dimensions`.
- `uploadToProvider` sends an ai-files file through the SDK's `uploadFile` and stores the reference; `providerFileParts` builds prompt parts from stored references.

## Consequences

Repeat calls send a reference. The provider owns the stored copy, so a deleted provider file needs a new upload.
