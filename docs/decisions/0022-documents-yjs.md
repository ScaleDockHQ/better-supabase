# 0022: Store Yjs documents as an update log, with yjs as an optional peer

- Status: accepted
- Date: 2026-10-13

## Context

Pages, deals and tickets need a body that several people edit at once.
Yjs is the CRDT most editors bind to (Tiptap, Lexical, CodeMirror,
BlockNote), and a Yjs document is a sequence of binary updates that merge in
any order. A collaboration server (y-websocket, Hocuspocus) usually holds the
document in memory and persists it. Supabase apps already have Postgres for
storage and Realtime for broadcast and presence, but no process that can
keep documents in memory. The `ai-files` module already has a logical
`documents` table (`ai_documents`), so the new tables need other physical
names.

## Decision

The `documents` SQL module keeps three tables: `documents` (one row per
subject and name), `document_updates` (an append-only log of Yjs updates as
`bytea`, with an identity sequence number) and `document_snapshots` (one
merged state per document and the last sequence number it contains). The
database never parses Yjs: `push_document_update` checks the size and the
caller's `documents.write` permission and the subject's write rules, then
appends the update. `open_document` and `pull_document_updates` return the
snapshot and the updates after it as base64. Each document has a private
Realtime topic, `documents:<id>`. Its `realtime.messages` policies let
readers receive and track presence, and only editors broadcast.

Compaction runs in JavaScript, because merging needs Yjs. Past
`compactAfter` updates since the snapshot, a push enqueues
`documents.compact` with the `jobs` module. `compactDocument` from
`better-supabase/yjs` merges the snapshot and the log with
`Y.mergeUpdates` and calls `compact_document` (service role or
`documents.manage`), which stores the state and deletes the updates it
covers in one transaction. A client that asks for updates compaction removed
gets the snapshot instead. With the versions module, a saved version holds
the merged state under subject type `document`.

`better-supabase/yjs` is an SDK adapter subpath: it owns no SQL and no
tables (ADR 0010). `yjs` is an optional peer: the provider imports it on
first use through a variable specifier, or takes the module as an option,
and types it structurally (`applyUpdate`, `mergeUpdates` and a document with
`on` and `off` for `update`). The entry imports no Node built-ins.

## Alternatives considered

- **A collaboration server (Hocuspocus, y-websocket).** It holds documents
  in memory, which needs a long-running process that Vercel Functions and
  Edge Functions don't give, and it would duplicate the access checks the
  database already makes.
- **Merging in Postgres.** No maintained Postgres extension parses Yjs, and
  a port of the update format to PL/pgSQL would have to follow every Yjs
  release.
- **Storing only the latest full state.** Every edit would rewrite the whole
  document and two concurrent writes would lose one of them. The log keeps
  each write an append.
- **Broadcast only, without the log.** A client that misses a broadcast
  would never see the edit, and a document with no one online would have no
  state.

## Consequences

Each edit is one insert and one broadcast, and the log grows until
compaction, so an app needs the `jobs` module or a scheduled sweep over
`documents_to_compact`. A burst of edits makes as many pushes; the provider
merges edits that wait behind a failed push into one. Revisit when a
maintained Postgres Yjs extension exists, or when Supabase Realtime can
persist a channel's messages.
