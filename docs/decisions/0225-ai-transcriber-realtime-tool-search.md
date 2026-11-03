# 0225: Add an AI SDK transcriber, a realtime token route and a catalog tool search

- Status: accepted
- Date: 2026-11-03

## Context

The activities block takes a `Transcriber`, realtime needs a guarded token endpoint and `toolSearch` ranks by keywords.

## Decision

- `aiTranscriber` wraps `transcribe`.
- `realtimeTokenRoute` identifies the caller, rate limits, mints through `mint` and records one row per token.
- `toolSearchFrom` gives `toolSearch` a catalog's ranking.
- eve's `supabaseDocumentBackend` already stores memory documents with optimistic versions, so no second backend ships. Steering, `step-start` and `reasoning-file` parts were already mapped in `messages.ts`.

## Consequences

Each is a small function over a port. No new entry points are needed.
