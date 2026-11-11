-- better-supabase module: unscoped
-- @bsb-block unscoped@1 managed
-- @bsb-hash sha256:c0229bed5f116365112eac5d84a5b39e79ef5f610654b38a72c9fcb7a915d8db
-- Event triggers and triggers on auth tables. They belong to no schema of the app, so a diff limited to some schemas never plans them; keeping them here puts them in one place to read.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create event trigger bsb_audit_forget_dropped on sql_drop
  when tag in ('DROP TABLE', 'DROP SCHEMA')
  execute function better_supabase.audit_forget_dropped();

create trigger "bsb_profile_email" after update of email on auth.users
  for each row execute function "better_supabase"."mirror_profile_email"();
