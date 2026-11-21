# 1153: Add blobUploadRoute for Vercel Blob client uploads

- Status: accepted
- Date: 2026-11-21

## Context

`@vercel/blob` 2.9.0 `handleUpload` takes `onBeforeGenerateToken` and `onUploadCompleted`, which is where permission checks belong.

## Decision

`blobUploadRoute` in `better-supabase/storage` takes the SDK's `handleUpload` (typed structurally) plus `authorize` and `onCompleted` returning a `Result`. A refusal keeps its status and a failed completion answers 500 so Vercel retries.

## Alternatives considered

Importing `@vercel/blob/client` in the core. Rejected: optional peers stay structural.

## Consequences

No new subpath. The export snapshot gains one export.
