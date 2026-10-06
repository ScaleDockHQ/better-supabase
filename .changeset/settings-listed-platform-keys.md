---
"better-supabase": patch
---

When `sql.modules.settings.options.schemas` lists platform keys, the `platform_settings` write policies accept only those keys, so `set_platform_setting` refuses a key the config doesn't list instead of storing it under the fallback permission. Without listed platform keys, writes work as before.
