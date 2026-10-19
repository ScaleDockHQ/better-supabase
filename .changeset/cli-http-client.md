---
"better-supabase": patch
---

Every CLI request to the Management API and GitHub now goes through one HTTP
client. It sends a `better-supabase/<version>` user agent, times out after 30
seconds, and logs each request under `--debug`. A request that gets no response
fails with the new `network_error` code. A command that reads a hosted project
without `SUPABASE_ACCESS_TOKEN` now fails with `auth_required` (exit code 3)
instead of `missing_value`.
