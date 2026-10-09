---
"better-supabase": patch
---

`verify_api_key` refuses a personal key while its user is banned in Supabase Auth (`banned_until` in the future) or soft-deleted. Before, only the configured disabled column stopped a personal key, so a banned user's key kept working after their sessions ended.
