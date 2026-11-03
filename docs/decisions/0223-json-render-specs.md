# 0223: Store json-render specs as one part and as documents

- Status: accepted
- Date: 2026-11-03

## Context

json-render streams a UI spec as `data-spec` patch parts. Saved as they arrive, a message holds dozens of parts.

## Decision

- `better-supabase/json-render` is structural: it applies patches, folds them into one flat part, validates structure and links to a catalog's `validate`. `@json-render/core` stays an optional peer.
- `assistant({ parts: { compact } })` rewrites the response before saving. The ai-files document kind `spec` (version 3) stores a spec as a document.

## Consequences

Saved messages stay small and a spec survives as a document. The renderer is the app's, with `@json-render/react`.
