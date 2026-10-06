---
"better-supabase": patch
---

The settings setters (`set_user_setting`, `set_organization_setting`, `set_platform_setting`) write `updated_by` and `updated_at` on the first insert too, so an adopted settings table whose `updated_by` has no `auth.uid()` default still records who set a key.
