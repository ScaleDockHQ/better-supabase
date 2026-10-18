---
"better-supabase": minor
---

Outgoing webhooks pick the body per endpoint. The new `standard` format (`standardEnvelope()`) writes the 0.8 body, `{ type, timestamp, data }` or an array of them for a batch endpoint, signed per Standard Webhooks like `cloudevents`. `sql upgrade` from 0.8 gives existing endpoints `format = 'standard'`, so their receivers keep working, and new endpoints get `blocks.webhooks-out.options.defaultFormat` (default `cloudevents`), which also covers an adopted table that doesn't map `format` or holds `null`. Set an endpoint's `format` to `cloudevents` once its receiver reads CloudEvents.
