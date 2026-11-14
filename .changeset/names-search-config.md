---
"better-supabase": patch
---

Fix: `better-supabase gen` accepts `search` (`{ title, body }` or `false`) on an
entity under `blocks.<name>.names`, as the config type and ADR 0831 already
allowed. It failed with "blocks.contacts.names: Invalid type".
