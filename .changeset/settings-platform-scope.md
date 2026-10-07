---
"better-supabase": minor
---

The settings block has a `platform` scope for product-wide settings: a `platform_settings` table, `get_platform_settings`, `set_platform_setting` and `reset_platform_setting`, and `client.platform` from `defineSettings({ platform })`. Each key names the platform permission that may change it (`permission`) and who reads it (`read`: `public`, `authenticated` or `staff`), so keys guarded by different permissions share one table; `options.platform` sets the defaults (`settings.manage`, a new platform-scope module permission). Platform keys with a JSON Schema get the same pg_jsonschema check.
