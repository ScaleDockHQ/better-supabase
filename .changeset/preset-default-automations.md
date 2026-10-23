---
"better-supabase": minor
---

Presets now install the automations and queue blocks their default automations and block timers need: `helpdesk`, `people`, `erp` and `automation` gain automations, and `crm`, `helpdesk`, `cms`, `itsm`, `claims`, `ai`, `ai-chat` and `ai-agents` gain the queue. `erp` turns on the `quotes.quote_to_order` default. The automations block takes `enable` and `disable` options with default automation keys. The content block publishes scheduled entries from a `content.publish` block timer, and its `publishSchedule` option and pg_cron job are removed.
