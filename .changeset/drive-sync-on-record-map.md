---
"better-supabase": minor
---

Drive sync skips unchanged nodes and can mark missing ones instead of deleting them.

- With the `imports` block installed, `drive_sync_batch` records each mirrored node in `import_records` (`source = 'drive:<connection>'`, `entity = 'drive_node'`) with a content hash. A node whose hash is unchanged is not written, and the function returns the number of nodes it wrote. The signature is unchanged. Without the imports block it behaves as before.
- `blocks.drive.options.sync.prune` is `'delete'` (the default, today's behavior) or `'mark'`, which keeps unlisted nodes and sets `missing_since` on their record. Legal holds keep their node in both modes. `'mark'` needs the imports block.
- Run `better-supabase upgrade` to refresh the function.
