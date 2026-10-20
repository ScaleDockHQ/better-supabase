---
"better-supabase": minor
---

An adopted `webhooks-out` endpoints table has to choose its body format.

Breaking config change: in adopt mode, when `columns.endpoints.format` maps no column, `sql sync` now refuses the config unless `blocks.webhooks-out.options.defaultFormat` is set. Without a format column every endpoint gets `defaultFormat`, whose default changed from the 0.8 body (`standard`) to `cloudevents` in 0.9, so receivers broke without any change to the config. Set `defaultFormat: "standard"` to keep the 0.8 body, `"cloudevents"` if your receivers read CloudEvents, or map a format column.

Doctor reports the same config as `BS344` (warning), and says whether the table has no `format` column or one the config doesn't map. The webhooks-out page lists `defaultFormat` and the version 3 columns, and the new 0.9 to 0.10 guide covers the change.
