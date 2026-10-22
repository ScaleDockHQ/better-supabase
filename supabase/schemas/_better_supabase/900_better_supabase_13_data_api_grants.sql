-- better-supabase module: data-api-grants
-- @bsb-block data-api-grants@1 managed
-- Writes the complete Data API privileges of the tables and functions in the `expose` config for anon, authenticated and service_role, or derives table grants from the policies. A project with default privileges turned off grants new tables to no Data API role.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- List tables and functions in `expose` (better-supabase.config.ts); `upgrade` rewrites the grants below.
-- Each listed table or function gets exactly the listed privileges: the rest is revoked.
-- RLS still decides which rows each role sees; grants decide whether the role reaches the table at all.

-- config.expose
revoke all on table "public"."customers" from public, anon, authenticated, service_role;
grant select, insert, update, delete on table "public"."customers" to authenticated;
grant select, insert, update, delete on table "public"."customers" to service_role;
revoke all on table "public"."contacts" from public, anon, authenticated, service_role;
grant select, insert, update, delete on table "public"."contacts" to authenticated;
grant select, insert, update, delete on table "public"."contacts" to service_role;
revoke all on table "public"."locations" from public, anon, authenticated, service_role;
grant select, insert, update, delete on table "public"."locations" to authenticated;
grant select, insert, update, delete on table "public"."locations" to service_role;
revoke all on table "public"."notes" from public, anon, authenticated, service_role;
grant select, insert, update, delete on table "public"."notes" to authenticated;
grant select, insert, update, delete on table "public"."notes" to service_role;
revoke all on table "public"."tags" from public, anon, authenticated, service_role;
grant select, insert, update, delete on table "public"."tags" to authenticated;
grant select, insert, update, delete on table "public"."tags" to service_role;
revoke all on table "public"."customer_tags" from public, anon, authenticated, service_role;
grant select, insert, update, delete on table "public"."customer_tags" to authenticated;
grant select, insert, update, delete on table "public"."customer_tags" to service_role;
revoke all on table "public"."organizations" from public, anon, authenticated, service_role;
grant select on table "public"."organizations" to authenticated;
grant select, insert, update, delete on table "public"."organizations" to service_role;
revoke all on table "public"."plans" from public, anon, authenticated, service_role;
grant select on table "public"."plans" to authenticated;
grant select, insert, update, delete on table "public"."plans" to service_role;
revoke all on table "public"."plan_features" from public, anon, authenticated, service_role;
grant select on table "public"."plan_features" to authenticated;
grant select, insert, update, delete on table "public"."plan_features" to service_role;
revoke all on table "public"."subscriptions" from public, anon, authenticated, service_role;
grant select on table "public"."subscriptions" to authenticated;
grant select, insert, update, delete on table "public"."subscriptions" to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;
