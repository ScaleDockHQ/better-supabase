---
"better-supabase": minor
---

`blocks.messaging.on` and `blocks.comments.on` keep record conversations and comments to the record types they list. `open_conversation` refuses another type with `MESSAGING_SUBJECT_UNSUPPORTED` and `create_comment` with `COMMENT_SUBJECT_UNSUPPORTED`, so registering a type in `config.records` for another block no longer opens conversations on it. Without `on`, every registered type is allowed as before.
