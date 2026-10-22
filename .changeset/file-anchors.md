---
"better-supabase": minor
---

Anchor messages and comments to a file. `fileAnchor(attachmentId, { page, region, start, end })` from `better-supabase/blocks/messaging` or `better-supabase/blocks/comments` points a top-level message at a page, a region of a page or video frame, or a moment or span of an attachment on the same record or conversation. `send_message` checks the shape and the file and fails with `MESSAGING_ANCHOR_INVALID` otherwise, and `anchoredTo(attachmentId)` on both clients lists a file's messages or comments. Other anchors, such as text ranges, are stored as before.
