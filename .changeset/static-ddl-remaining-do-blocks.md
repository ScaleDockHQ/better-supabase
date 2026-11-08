---
"better-supabase": minor
---

The generated schema files hold 4 top-level `do` blocks, down from 27. The catalog's row level security and audit triggers are plain statements, the `webhook-inbox` key is one `add constraint`, and the attachments path and storage status backfills, the legal-entities duplicate-number warning and the vector search index notice move to the module data files. The profiles username check stays `not valid` and is never validated for you; run `alter table ... validate constraint bsb_profiles_username_check` once no profile breaks it. `publish_webhook_event` builds an endpoint's held grants by the provider's `wildcards` setting. Installed apps run `better-supabase upgrade`, then the Supabase CLI sync, then `better-supabase add --adopt`.
