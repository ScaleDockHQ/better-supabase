---
"better-supabase": patch
---

The profiles module's `update_my_profile(attrs)` writes `avatar_path`, so users can save the Storage path of an uploaded avatar through the same RPC as their name. An adopted table needs an `avatarPath` column mapping for it.
