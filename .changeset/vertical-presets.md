---
"better-supabase": minor
---

`better-supabase/preset` adds 17 vertical presets in a new `verticals` group (`PRESET_GROUPS.verticals`), so `/create` and `init` list them under Verticals: `property`, `field-service`, `clinic`, `lms`, `events`, `legal`, `spend`, `contracts`, `customer-success`, `logistics`, `pos`, `fitness`, `nonprofit`, `itsm`, `compliance`, `construction` and `claims`. Each one is `saas` plus the blocks of one kind of business app, such as leases on the ledger for property management, a dispatch board for field service or controls with recurring evidence for compliance, and each has a page under [Presets](https://bettersupabase.com/docs/presets). The `clinic` preset installs `field-encryption`; its page shows the config for encrypted columns and read audits, which name your own tables and so stay in your config. Existing presets and preset codes keep their blocks.
