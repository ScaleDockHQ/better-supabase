---
"better-supabase": minor
---

Block clients built from a `Db` get its Storage:

- `db.<block>` and `db.$blocks.<block>` clients, `blockSet.client(db, key)` and `createBlockClient(db, block)` pass `db.$storage` to the block as `storage` when the `Db` has Storage, so `db.$blocks.attachments`, `db.$blocks.dataLifecycle`, ai-files and drive read, sign and remove files as the `Db`'s caller instead of failing without one. A `storage` you pass through `options` or `.with({ storage })` still wins.
- `BlockContext`, `BlockClientOptions` and `CreateBlocksOptions` take `storage`, and the options `.using(create)` passes its creator hold it.
