-- better-supabase module: unscoped
-- @bsb-block unscoped@1 managed
-- @bsb-hash sha256:58f8ba9bd4837af5e9ec305cc01f2bc10c598576d58e11cf70588dee31c9df10
-- Event triggers and triggers on auth tables. They belong to no schema of the app, so a diff limited to some schemas never plans them; keeping them here puts them in one place to read.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create event trigger bsb_audit_forget_dropped on sql_drop
  when tag in ('DROP TABLE', 'DROP SCHEMA')
  execute function better_supabase.audit_forget_dropped();

create trigger "bsb_profile_sync" after insert on auth.users
  for each row execute function "better_supabase"."on_auth_user_created"();

create trigger "bsb_profile_email" after update of email on auth.users
  for each row execute function "better_supabase"."mirror_profile_email"();

create trigger "bsb_sso_auth_user" after insert or update of email, email_confirmed_at on auth.users
  for each row execute function "better_supabase"."sso_on_auth_user"();

create trigger "bsb_waitlist_auth_user" after insert on auth.users
  for each row execute function "better_supabase"."waitlist_on_auth_user"();

create trigger "bsb_identity_email" after insert or update of email, email_confirmed_at on auth.users
  for each row execute function "better_supabase"."on_auth_user_email"();
