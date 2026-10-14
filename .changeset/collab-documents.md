---
"better-supabase": minor
---

Add the `documents` block (`better-supabase/blocks/documents` and the `documents` SQL module) and the `better-supabase/yjs` provider. A document is a Yjs update log and a compacted snapshot attached to any subject, with a private `documents:<id>` Realtime topic for edits and presence under the subject's read and write rules. `createDocumentProvider` connects a `Y.Doc`: it loads the stored state, stores and broadcasts each edit, and catches up after a reconnect. `compactDocument` merges the log for the `documents.compact` job, and with the versions module a document's state can be saved as a version. `yjs` (`>=13.6 <14`) is a new optional peer.
