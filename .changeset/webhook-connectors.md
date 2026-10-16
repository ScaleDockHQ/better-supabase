---
"better-supabase": minor
---

Outgoing webhooks write each endpoint's `format` with a versioned `WebhookEncoder`. `cloudEvents()` stays the default; `otlpLogs()` sends OTLP/HTTP JSON logs to a collector and `splunkHec()` sends Splunk HTTP Event Collector events. An endpoint's `credential_ref` adds the token from the new `credentials` option, and an encoder's `classify` reads responses such as an OTLP partial success or an HEC error code inside a 200.
