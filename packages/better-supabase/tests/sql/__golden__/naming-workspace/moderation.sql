-- ==== schema supabase/schemas/900_better_supabase_108_moderation.sql
-- better-supabase module: moderation
-- @bsb-block moderation@2 managed
-- @bsb-hash sha256:166fe7f42001b3d892abb2d464cfb185265e43698d6f8de58a4c5b3b975162e3
-- Reports on any subject, a review queue, decisions (approve, hide, remove, restore, ban) with a log, user bans and an automatic hide threshold. Reviews moderate through it, and it hides and removes messages, comments included.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."moderation_items";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."moderation_items";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."moderation_items";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."moderation_items";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."moderation_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."moderation_reports";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."moderation_reports";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."moderation_reports";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."moderation_reports";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."moderation_reports";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."moderation_actions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."moderation_actions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."moderation_actions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."moderation_actions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."moderation_actions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."moderation_bans";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."moderation_bans";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."moderation_bans";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."moderation_bans";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."moderation_bans";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."moderation_statements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."moderation_statements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."moderation_statements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."moderation_statements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."moderation_statements";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."moderation_notices";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."moderation_notices";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."moderation_notices";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."moderation_notices";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."moderation_notices";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."moderation_flaggers";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."moderation_flaggers";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."moderation_flaggers";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."moderation_flaggers";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."moderation_flaggers";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."moderation_appeals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."moderation_appeals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."moderation_appeals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."moderation_appeals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."moderation_appeals";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."moderation_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "author_id" uuid references auth.users (id) on delete set null,
  "status" text not null default 'visible' check ("status" in ('pending', 'visible', 'hidden', 'removed')),
  "open_reports" integer not null default 0 check ("open_reports" >= 0),
  "reason" text check ("reason" is null or length("reason") <= 1000),
  "decided_by" uuid,
  "decided_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "subject_type", "subject_id")
);
create index if not exists "moderation_items_queue_idx" on "better_supabase"."moderation_items" ("tenant_id", "updated_at" desc) where "status" = 'pending' or "open_reports" > 0;
create index if not exists "moderation_items_status_idx" on "better_supabase"."moderation_items" ("tenant_id", "status", "updated_at" desc);
create index if not exists "moderation_items_author_idx" on "better_supabase"."moderation_items" ("author_id");

create table if not exists "better_supabase"."moderation_reports" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "item_id" uuid not null references "better_supabase"."moderation_items" ("id") on delete cascade,
  "reporter_id" uuid references auth.users (id) on delete cascade,
  "reason" text not null check ("reason" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "note" text check ("note" is null or length("note") <= 1000),
  "status" text not null default 'open' check ("status" in ('open', 'resolved', 'dismissed')),
  "resolved_by" uuid,
  "resolved_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create unique index if not exists "moderation_reports_open_idx" on "better_supabase"."moderation_reports" ("item_id", "reporter_id") where "status" = 'open';
create index if not exists "moderation_reports_item_idx" on "better_supabase"."moderation_reports" ("item_id", "created_at" desc);
create index if not exists "moderation_reports_reporter_idx" on "better_supabase"."moderation_reports" ("reporter_id");

create table if not exists "better_supabase"."moderation_actions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "item_id" uuid not null references "better_supabase"."moderation_items" ("id") on delete cascade,
  "action" text not null check ("action" in ('submit', 'approve', 'hide', 'remove', 'restore', 'ban', 'auto_hide')),
  "from_status" text,
  "to_status" text not null,
  "reason" text,
  "actor_id" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists "moderation_actions_item_idx" on "better_supabase"."moderation_actions" ("item_id", "created_at" desc);

create table if not exists "better_supabase"."moderation_bans" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "reason" text check ("reason" is null or length("reason") <= 1000),
  "banned_by" uuid,
  "expires_at" timestamptz,
  "lifted_by" uuid,
  "lifted_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create unique index if not exists "moderation_bans_active_idx" on "better_supabase"."moderation_bans" ("tenant_id", "user_id") where "lifted_at" is null;
create index if not exists "moderation_bans_user_idx" on "better_supabase"."moderation_bans" ("user_id");

-- Statements of reasons (DSA Article 17): what was restricted, the facts, the
-- legal or contractual ground, automated means and the ways to appeal.
create table if not exists "better_supabase"."moderation_statements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "item_id" uuid not null references "better_supabase"."moderation_items" ("id") on delete cascade,
  "restriction" text not null check ("restriction" in ('removal', 'disabled_access', 'demotion', 'visibility_suspension', 'monetary_suspension', 'service_suspension', 'service_termination', 'account_suspension', 'account_termination')),
  "facts" text not null check (length("facts") between 1 and 5000),
  "legal_ground" text check ("legal_ground" is null or length("legal_ground") <= 2000),
  "terms_ground" text check ("terms_ground" is null or length("terms_ground") <= 2000),
  "automated_detection" boolean not null default false,
  "automated_decision" boolean not null default false,
  "redress" text[] not null default array['internal_complaint', 'out_of_court', 'judicial'],
  "issued_by" uuid,
  "created_at" timestamptz not null default now(),
  check ("legal_ground" is not null or "terms_ground" is not null)
);
create index if not exists "moderation_statements_item_idx" on "better_supabase"."moderation_statements" ("item_id", "created_at" desc);
create index if not exists "moderation_statements_tenant_idx" on "better_supabase"."moderation_statements" ("tenant_id", "created_at" desc);

-- Notices of illegal content (DSA Article 16).
create table if not exists "better_supabase"."moderation_notices" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "item_id" uuid references "better_supabase"."moderation_items" ("id") on delete set null,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "explanation" text not null check (length("explanation") between 1 and 5000),
  "url" text check ("url" is null or length("url") <= 2000),
  "notifier_name" text check ("notifier_name" is null or length("notifier_name") <= 200),
  "notifier_email" text check ("notifier_email" is null or length("notifier_email") <= 320),
  "notifier_id" uuid references auth.users (id) on delete set null,
  "trusted" boolean not null default false,
  "status" text not null default 'received' check ("status" in ('received', 'actioned', 'rejected')),
  "outcome" text check ("outcome" is null or length("outcome") <= 2000),
  "decided_by" uuid,
  "decided_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists "moderation_notices_queue_idx" on "better_supabase"."moderation_notices" ("tenant_id", "trusted" desc, "created_at") where "status" = 'received';
create index if not exists "moderation_notices_notifier_idx" on "better_supabase"."moderation_notices" ("notifier_id");
create index if not exists "moderation_notices_item_idx" on "better_supabase"."moderation_notices" ("item_id");

-- Trusted flaggers (DSA Article 22): notices from them are marked and come
-- first in the queue.
create table if not exists "better_supabase"."moderation_flaggers" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "name" text not null check (length("name") between 1 and 200),
  "awarded_by" text check ("awarded_by" is null or length("awarded_by") <= 200),
  "revoked_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create unique index if not exists "moderation_flaggers_active_idx" on "better_supabase"."moderation_flaggers" ("tenant_id", "user_id") where "revoked_at" is null;
create index if not exists "moderation_flaggers_user_idx" on "better_supabase"."moderation_flaggers" ("user_id");

-- Appeals (DSA Article 20) against a statement of reasons or a rejected notice.
create table if not exists "better_supabase"."moderation_appeals" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "statement_id" uuid references "better_supabase"."moderation_statements" ("id") on delete cascade,
  "notice_id" uuid references "better_supabase"."moderation_notices" ("id") on delete cascade,
  "appellant_id" uuid references auth.users (id) on delete set null,
  "reasons" text not null check (length("reasons") between 1 and 5000),
  "status" text not null default 'open' check ("status" in ('open', 'upheld', 'reversed')),
  "outcome" text check ("outcome" is null or length("outcome") <= 2000),
  "decided_by" uuid,
  "decided_at" timestamptz,
  "created_at" timestamptz not null default now(),
  check (("statement_id" is not null) <> ("notice_id" is not null))
);
create unique index if not exists "moderation_appeals_open_statement_idx" on "better_supabase"."moderation_appeals" ("statement_id") where "status" = 'open' and "statement_id" is not null;
create unique index if not exists "moderation_appeals_open_notice_idx" on "better_supabase"."moderation_appeals" ("notice_id") where "status" = 'open' and "notice_id" is not null;
create index if not exists "moderation_appeals_tenant_idx" on "better_supabase"."moderation_appeals" ("tenant_id", "created_at" desc);
create index if not exists "moderation_appeals_appellant_idx" on "better_supabase"."moderation_appeals" ("appellant_id");

alter table "better_supabase"."moderation_items" enable row level security;
revoke all on "better_supabase"."moderation_items" from public, anon, authenticated;
grant select on "better_supabase"."moderation_items" to authenticated;
grant all on "better_supabase"."moderation_items" to service_role;
drop policy if exists "moderation_items_read" on "better_supabase"."moderation_items";
create policy moderation_items_read on "better_supabase"."moderation_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')));
alter table "better_supabase"."moderation_reports" enable row level security;
revoke all on "better_supabase"."moderation_reports" from public, anon, authenticated;
grant select on "better_supabase"."moderation_reports" to authenticated;
grant all on "better_supabase"."moderation_reports" to service_role;
drop policy if exists "moderation_reports_read" on "better_supabase"."moderation_reports";
create policy moderation_reports_read on "better_supabase"."moderation_reports"
  for select to authenticated
  using ("reporter_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')));
alter table "better_supabase"."moderation_actions" enable row level security;
revoke all on "better_supabase"."moderation_actions" from public, anon, authenticated;
grant select on "better_supabase"."moderation_actions" to authenticated;
grant all on "better_supabase"."moderation_actions" to service_role;
drop policy if exists "moderation_actions_read" on "better_supabase"."moderation_actions";
create policy moderation_actions_read on "better_supabase"."moderation_actions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')));
alter table "better_supabase"."moderation_bans" enable row level security;
revoke all on "better_supabase"."moderation_bans" from public, anon, authenticated;
grant select on "better_supabase"."moderation_bans" to authenticated;
grant all on "better_supabase"."moderation_bans" to service_role;
drop policy if exists "moderation_bans_read" on "better_supabase"."moderation_bans";
create policy moderation_bans_read on "better_supabase"."moderation_bans"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')));

alter table "better_supabase"."moderation_statements" enable row level security;
revoke all on "better_supabase"."moderation_statements" from public, anon, authenticated;
grant select on "better_supabase"."moderation_statements" to authenticated;
grant all on "better_supabase"."moderation_statements" to service_role;
drop policy if exists "moderation_statements_read" on "better_supabase"."moderation_statements";
create policy moderation_statements_read on "better_supabase"."moderation_statements"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')));
alter table "better_supabase"."moderation_notices" enable row level security;
revoke all on "better_supabase"."moderation_notices" from public, anon, authenticated;
grant select on "better_supabase"."moderation_notices" to authenticated;
grant all on "better_supabase"."moderation_notices" to service_role;
drop policy if exists "moderation_notices_read" on "better_supabase"."moderation_notices";
create policy moderation_notices_read on "better_supabase"."moderation_notices"
  for select to authenticated
  using ("notifier_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')));
alter table "better_supabase"."moderation_flaggers" enable row level security;
revoke all on "better_supabase"."moderation_flaggers" from public, anon, authenticated;
grant select on "better_supabase"."moderation_flaggers" to authenticated;
grant all on "better_supabase"."moderation_flaggers" to service_role;
drop policy if exists "moderation_flaggers_read" on "better_supabase"."moderation_flaggers";
create policy moderation_flaggers_read on "better_supabase"."moderation_flaggers"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')));
alter table "better_supabase"."moderation_appeals" enable row level security;
revoke all on "better_supabase"."moderation_appeals" from public, anon, authenticated;
grant select on "better_supabase"."moderation_appeals" to authenticated;
grant all on "better_supabase"."moderation_appeals" to service_role;
drop policy if exists "moderation_appeals_read" on "better_supabase"."moderation_appeals";
create policy moderation_appeals_read on "better_supabase"."moderation_appeals"
  for select to authenticated
  using ("appellant_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')));

-- Whether a user is banned in an organization right now.
create or replace function "better_supabase"."moderation_banned"(tenant uuid, user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select moderation_banned.user_id is not null and exists (
    select 1 from "better_supabase"."moderation_bans" x
    where x."tenant_id" = moderation_banned.tenant and x."user_id" = moderation_banned.user_id and x."lifted_at" is null and (x."expires_at" is null or x."expires_at" > now())
  )
$$;
revoke execute on function "better_supabase"."moderation_banned"(uuid, uuid) from public, anon, authenticated;

-- Puts a subject under moderation, or puts it back after its author changed
-- it: status pending waits for a decision, visible shows it. Clears the last
-- decision. For modules that moderate their own content, such as reviews.
create or replace function "better_supabase"."moderation_track"(tenant uuid, subject_type text, subject_id text, author uuid, status text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old "better_supabase"."moderation_items";
  v_row "better_supabase"."moderation_items";
begin
  if moderation_track.status not in ('pending', 'visible') then
    raise exception 'content starts pending or visible' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  select * into v_old from "better_supabase"."moderation_items" x
  where x."tenant_id" = moderation_track.tenant and x."subject_type" = moderation_track.subject_type and x."subject_id" = moderation_track.subject_id
  for update;
  if v_old."id" is null then
    insert into "better_supabase"."moderation_items" ("tenant_id", "subject_type", "subject_id", "author_id", "status")
    values (moderation_track.tenant, moderation_track.subject_type, moderation_track.subject_id, moderation_track.author, moderation_track.status)
    returning * into v_row;
  else
    update "better_supabase"."moderation_items" x
    set "status" = moderation_track.status, "author_id" = coalesce(moderation_track.author, x."author_id"),
      "reason" = null, "decided_by" = null, "decided_at" = null, "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  if v_old."status" is distinct from v_row."status" then
    insert into "better_supabase"."moderation_actions" ("tenant_id", "item_id", "action", "from_status", "to_status", "actor_id")
    values (v_row."tenant_id", v_row."id", 'submit', v_old."status", v_row."status", moderation_track.author);
  end if;
  return v_row."id";
end;
$$;
revoke execute on function "better_supabase"."moderation_track"(uuid, text, text, uuid, text) from public, anon, authenticated;

-- Applies a decision without a permission check: approve and restore show
-- the content, hide and auto_hide hide it, remove and ban remove it, and ban
-- also bans its author. Closes the open reports, except on auto_hide, and
-- logs the action.
create or replace function "better_supabase"."moderation_apply"(item_id uuid, action text, reason text default null, automatic boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old "better_supabase"."moderation_items";
  v_row "better_supabase"."moderation_items";
  v_ban "better_supabase"."moderation_bans";
  v_status text;
begin
  select * into v_old from "better_supabase"."moderation_items" x where x."id" = moderation_apply.item_id for update;
  if v_old."id" is null then
    raise exception 'moderation item not found' using errcode = 'P0002', hint = 'MODERATION_ITEM_NOT_FOUND';
  end if;
  v_status := case moderation_apply.action
    when 'approve' then 'visible'
    when 'restore' then 'visible'
    when 'hide' then 'hidden'
    when 'auto_hide' then 'hidden'
    when 'remove' then 'removed'
    when 'ban' then 'removed'
  end;
  if v_status is null then
    raise exception 'action must be approve, hide, remove, restore or ban' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if length(moderation_apply.reason) > 1000 then
    raise exception 'reason must be at most 1000 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if moderation_apply.action = 'restore' and v_old."status" not in ('hidden', 'removed') then
    raise exception 'only hidden or removed content can be restored' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if moderation_apply.action = 'ban' and v_old."author_id" is null then
    raise exception 'this content has no author to ban' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  update "better_supabase"."moderation_items" x
  set "status" = v_status,
    "reason" = case when v_status = 'visible' then null else nullif(trim(moderation_apply.reason), '') end,
    "decided_by" = case when moderation_apply.automatic then null else auth.uid() end,
    "decided_at" = now(),
    "open_reports" = case when moderation_apply.action = 'auto_hide' then x."open_reports" else 0 end,
    "updated_at" = now()
  where x."id" = v_old."id"
  returning * into v_row;
  if moderation_apply.action <> 'auto_hide' then
    update "better_supabase"."moderation_reports" x
    set "status" = case when v_status = 'visible' then 'dismissed' else 'resolved' end,
      "resolved_by" = auth.uid(), "resolved_at" = now()
    where x."item_id" = v_row."id" and x."status" = 'open';
  end if;
  insert into "better_supabase"."moderation_actions" ("tenant_id", "item_id", "action", "from_status", "to_status", "reason", "actor_id")
  values (v_row."tenant_id", v_row."id", moderation_apply.action, v_old."status", v_status, nullif(trim(moderation_apply.reason), ''),
    case when moderation_apply.automatic then null else auth.uid() end);
  if moderation_apply.action = 'ban' and not "better_supabase"."moderation_banned"(v_row."tenant_id", v_row."author_id") then
    delete from "better_supabase"."moderation_bans" x where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."author_id" and x."lifted_at" is null;
    insert into "better_supabase"."moderation_bans" ("tenant_id", "user_id", "reason", "banned_by")
    values (v_row."tenant_id", v_row."author_id", nullif(trim(moderation_apply.reason), ''), auth.uid())
    returning * into v_ban;
    null;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'status', v_row."status", 'openReports', v_row."open_reports", 'reason', v_row."reason", 'decidedBy', v_row."decided_by", 'decidedAt', v_row."decided_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."moderation_apply"(uuid, text, text, boolean) from public, anon, authenticated;

-- Reports a subject for a reason (spam, abuse, harassment, off_topic, illegal, other). A member reports a
-- subject once until a moderator decides on it; reporting again returns the
-- open report. Content with 3 open reports is hidden until a moderator decides.
create or replace function "better_supabase"."report_content"(tenant uuid, subject_type text, subject_id text, reason text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_author uuid;
  v_item "better_supabase"."moderation_items";
  v_report "better_supabase"."moderation_reports";
  v_auto boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to report content' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if not coalesce(better_supabase.can('tenant', report_content.tenant, 'moderation.report'), false) then
    raise exception 'not allowed to report content' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if "better_supabase"."moderation_banned"(report_content.tenant, v_me) then
    raise exception 'you are banned in this organization' using errcode = '42501', hint = 'MODERATION_BANNED';
  end if;
  if report_content.reason is null or report_content.reason not in ('spam', 'abuse', 'harassment', 'off_topic', 'illegal', 'other') then
    raise exception 'reason must be one of spam, abuse, harassment, off_topic, illegal, other' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if length(report_content.note) > 1000 then
    raise exception 'note must be at most 1000 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if report_content.subject_type is null or report_content.subject_type !~ '^[a-z][a-z0-9_-]{0,62}$'
    or report_content.subject_id is null or length(report_content.subject_id) not between 1 and 200 then
    raise exception 'a report needs a subject type and id' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  insert into "better_supabase"."moderation_items" ("tenant_id", "subject_type", "subject_id", "author_id")
  values (report_content.tenant, report_content.subject_type, report_content.subject_id, v_author)
  on conflict ("tenant_id", "subject_type", "subject_id") do nothing;
  select * into v_item from "better_supabase"."moderation_items" x
  where x."tenant_id" = report_content.tenant and x."subject_type" = report_content.subject_type and x."subject_id" = report_content.subject_id
  for update;
  if v_item."author_id" = v_me then
    raise exception 'you can''t report your own content' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  insert into "better_supabase"."moderation_reports" ("tenant_id", "item_id", "reporter_id", "reason", "note")
  values (report_content.tenant, v_item."id", v_me, report_content.reason, nullif(trim(report_content.note), ''))
  on conflict ("item_id", "reporter_id") where "status" = 'open' do nothing
  returning * into v_report;
  if v_report."id" is null then
    select * into v_report from "better_supabase"."moderation_reports" x
    where x."item_id" = v_item."id" and x."reporter_id" = v_me and x."status" = 'open';
    return jsonb_build_object('id', v_report."id", 'organizationId', v_report."tenant_id", 'itemId', v_report."item_id", 'reporterId', v_report."reporter_id", 'reason', v_report."reason", 'note', v_report."note", 'status', v_report."status", 'resolvedBy', v_report."resolved_by", 'resolvedAt', v_report."resolved_at", 'createdAt', v_report."created_at") || jsonb_build_object('autoHidden', false);
  end if;
  update "better_supabase"."moderation_items" x
  set "open_reports" = (select count(*) from "better_supabase"."moderation_reports" y where y."item_id" = x."id" and y."status" = 'open'),
    "updated_at" = now()
  where x."id" = v_item."id"
  returning * into v_item;
  null;
  if v_item."status" = 'visible' and v_item."open_reports" >= 3 then
    perform "better_supabase"."moderation_apply"(v_item."id", 'auto_hide', 'Hidden after 3 reports', true);
    v_auto := true;
  end if;
  return jsonb_build_object('id', v_report."id", 'organizationId', v_report."tenant_id", 'itemId', v_report."item_id", 'reporterId', v_report."reporter_id", 'reason', v_report."reason", 'note', v_report."note", 'status', v_report."status", 'resolvedBy', v_report."resolved_by", 'resolvedAt', v_report."resolved_at", 'createdAt', v_report."created_at") || jsonb_build_object('autoHidden', v_auto);
end;
$$;
revoke execute on function "better_supabase"."report_content"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."report_content"(uuid, text, text, text, text) to authenticated, service_role;

-- A moderator's decision on an item: approve, hide, remove, restore, or ban
-- (remove the content and ban its author, which also needs the ban
-- permission).
create or replace function "better_supabase"."moderate"(item_id uuid, action text, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."moderation_items" x where x."id" = moderate.item_id;
  if not found then
    raise exception 'moderation item not found' using errcode = 'P0002', hint = 'MODERATION_ITEM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'moderation.manage'), false)) then
    raise exception 'not allowed to moderate content' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if moderate.action = 'ban' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'moderation.ban'), false)) then
    raise exception 'not allowed to ban users' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if moderate.action = 'auto_hide' then
    raise exception 'auto_hide is the module''s own action' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  return "better_supabase"."moderation_apply"(moderate.item_id, moderate.action, moderate.reason, false);
end;
$$;
revoke execute on function "better_supabase"."moderate"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."moderate"(uuid, text, text) to authenticated, service_role;

-- The review queue, most recently changed first. Without a status it holds
-- what needs a moderator: pending content and content with open reports.
create or replace function "better_supabase"."moderation_queue"(tenant uuid, status text default null, subject_type text default null, page_size integer default 50, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', moderation_queue.tenant, 'moderation.read'), false)) then
    raise exception 'not allowed to read the moderation queue' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.updated desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'status', x."status", 'openReports', x."open_reports", 'reason', x."reason", 'decidedBy', x."decided_by", 'decidedAt', x."decided_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."updated_at" as updated, x."id" as id
    from "better_supabase"."moderation_items" x
    where x."tenant_id" = moderation_queue.tenant
      and (case when moderation_queue.status is null then x."status" = 'pending' or x."open_reports" > 0 else x."status" = moderation_queue.status end)
      and (moderation_queue.subject_type is null or x."subject_type" = moderation_queue.subject_type)
      and (moderation_queue.before is null or x."updated_at" < moderation_queue.before)
    order by x."updated_at" desc, x."id" desc
    limit least(greatest(coalesce(moderation_queue.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."moderation_queue"(uuid, text, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."moderation_queue"(uuid, text, text, integer, timestamptz) to authenticated, service_role;

-- One subject's item with its latest 100 reports and actions, or null when
-- nothing moderated it.
create or replace function "better_supabase"."moderation_item"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."moderation_items";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', moderation_item.tenant, 'moderation.read'), false)) then
    raise exception 'not allowed to read moderation' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."moderation_items" x
  where x."tenant_id" = moderation_item.tenant and x."subject_type" = moderation_item.subject_type and x."subject_id" = moderation_item.subject_id;
  if v_row."id" is null then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'status', v_row."status", 'openReports', v_row."open_reports", 'reason', v_row."reason", 'decidedBy', v_row."decided_by", 'decidedAt', v_row."decided_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'reports', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'itemId', y."item_id", 'reporterId', y."reporter_id", 'reason', y."reason", 'note', y."note", 'status', y."status", 'resolvedBy', y."resolved_by", 'resolvedAt', y."resolved_at", 'createdAt', y."created_at") order by y."created_at" desc) from (select * from "better_supabase"."moderation_reports" z where z."item_id" = v_row."id" order by z."created_at" desc limit 100) y), '[]'::jsonb),
    'actions', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'action', y."action", 'fromStatus', y."from_status", 'toStatus', y."to_status", 'reason', y."reason", 'actorId', y."actor_id", 'createdAt', y."created_at") order by y."created_at" desc) from (select * from "better_supabase"."moderation_actions" z where z."item_id" = v_row."id" order by z."created_at" desc limit 100) y), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."moderation_item"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."moderation_item"(uuid, text, text) to authenticated, service_role;

-- The subjects of up to 500 ids that are not visible, as { id: status }, for
-- members filtering a list. Visible and unmoderated subjects are left out.
create or replace function "better_supabase"."moderation_statuses"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_out jsonb;
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', moderation_statuses.tenant, 'moderation.report'), false)) or coalesce(better_supabase.can('tenant', moderation_statuses.tenant, 'moderation.read'), false)) then
    raise exception 'not allowed to read moderation' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  select coalesce(jsonb_object_agg(x."subject_id", x."status"), '{}'::jsonb) into v_out
  from "better_supabase"."moderation_items" x
  where x."tenant_id" = moderation_statuses.tenant and x."subject_type" = moderation_statuses.subject_type
    and x."subject_id" = any (moderation_statuses.subject_ids[1:500]) and x."status" <> 'visible';
  return v_out;
end;
$$;
revoke execute on function "better_supabase"."moderation_statuses"(uuid, text, text[]) from public, anon;
grant execute on function "better_supabase"."moderation_statuses"(uuid, text, text[]) to authenticated, service_role;

-- Bans a user in an organization until expires_at, or for good. Banning a
-- banned user changes the reason and the end.
create or replace function "better_supabase"."ban_user"(tenant uuid, user_id uuid, reason text default null, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."moderation_bans";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', ban_user.tenant, 'moderation.ban'), false)) then
    raise exception 'not allowed to ban users' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if ban_user.user_id is null or ban_user.user_id = auth.uid() then
    raise exception 'pick another user to ban' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if ban_user.expires_at is not null and ban_user.expires_at <= now() then
    raise exception 'expires_at must be in the future' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if length(ban_user.reason) > 1000 then
    raise exception 'reason must be at most 1000 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  delete from "better_supabase"."moderation_bans" x where x."tenant_id" = ban_user.tenant and x."user_id" = ban_user.user_id and x."lifted_at" is null and x."expires_at" <= now();
  insert into "better_supabase"."moderation_bans" ("tenant_id", "user_id", "reason", "banned_by", "expires_at")
  values (ban_user.tenant, ban_user.user_id, nullif(trim(ban_user.reason), ''), auth.uid(), ban_user.expires_at)
  on conflict ("tenant_id", "user_id") where "lifted_at" is null do update
    set "reason" = excluded."reason", "banned_by" = excluded."banned_by", "expires_at" = excluded."expires_at"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'reason', v_row."reason", 'bannedBy', v_row."banned_by", 'expiresAt', v_row."expires_at", 'liftedBy', v_row."lifted_by", 'liftedAt', v_row."lifted_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."ban_user"(uuid, uuid, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."ban_user"(uuid, uuid, text, timestamptz) to authenticated, service_role;

-- Lifts a ban. False when it was already lifted.
create or replace function "better_supabase"."unban_user"(ban_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."moderation_bans";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."moderation_bans" x where x."id" = unban_user.ban_id for update;
  if v_row."id" is null then
    raise exception 'ban not found' using errcode = 'P0002', hint = 'MODERATION_BAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'moderation.ban'), false)) then
    raise exception 'not allowed to lift bans' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if v_row."lifted_at" is not null then
    return false;
  end if;
  update "better_supabase"."moderation_bans" x set "lifted_at" = now(), "lifted_by" = auth.uid()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."unban_user"(uuid) from public, anon;
grant execute on function "better_supabase"."unban_user"(uuid) to authenticated, service_role;

-- An organization's bans, newest first: active ones by default.
create or replace function "better_supabase"."list_bans"(tenant uuid, active boolean default true, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_bans.tenant, 'moderation.read'), false)) then
    raise exception 'not allowed to read bans' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.created desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'reason', x."reason", 'bannedBy', x."banned_by", 'expiresAt', x."expires_at", 'liftedBy', x."lifted_by", 'liftedAt', x."lifted_at", 'createdAt', x."created_at") as item, x."created_at" as created, x."id" as id
    from "better_supabase"."moderation_bans" x
    where x."tenant_id" = list_bans.tenant
      and (not coalesce(list_bans.active, false) or (x."lifted_at" is null and (x."expires_at" is null or x."expires_at" > now())))
    order by x."created_at" desc, x."id" desc
    limit least(greatest(coalesce(list_bans.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_bans"(uuid, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_bans"(uuid, boolean, integer) to authenticated, service_role;

-- Takes a notice of illegal content (DSA Article 16) for a subject. The
-- notice is marked trusted when the caller is an active trusted flagger, and
-- the subject gets a moderation item when it has none.
create or replace function "better_supabase"."submit_notice"(tenant uuid, subject_type text, subject_id text, explanation text, url text default null, notifier_name text default null, notifier_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_item uuid;
  v_trusted boolean;
  v_row "better_supabase"."moderation_notices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to submit a notice' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if not coalesce(better_supabase.can('tenant', submit_notice.tenant, 'moderation.report'), false) then
    raise exception 'not allowed to submit a notice' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if submit_notice.subject_type is null or submit_notice.subject_type !~ '^[a-z][a-z0-9_-]{0,62}$'
    or submit_notice.subject_id is null or length(submit_notice.subject_id) not between 1 and 200 then
    raise exception 'a notice needs a subject type and id' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if submit_notice.explanation is null or length(trim(submit_notice.explanation)) = 0 or length(submit_notice.explanation) > 5000 then
    raise exception 'a notice needs an explanation of at most 5000 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  insert into "better_supabase"."moderation_items" ("tenant_id", "subject_type", "subject_id")
  values (submit_notice.tenant, submit_notice.subject_type, submit_notice.subject_id)
  on conflict ("tenant_id", "subject_type", "subject_id") do nothing;
  select x."id" into v_item from "better_supabase"."moderation_items" x
  where x."tenant_id" = submit_notice.tenant and x."subject_type" = submit_notice.subject_type and x."subject_id" = submit_notice.subject_id;
  select exists (
    select 1 from "better_supabase"."moderation_flaggers" x
    where x."tenant_id" = submit_notice.tenant and x."user_id" = v_me and x."revoked_at" is null
  ) into v_trusted;
  insert into "better_supabase"."moderation_notices" ("tenant_id", "item_id", "subject_type", "subject_id", "explanation", "url", "notifier_name", "notifier_email", "notifier_id", "trusted")
  values (submit_notice.tenant, v_item, submit_notice.subject_type, submit_notice.subject_id, trim(submit_notice.explanation), nullif(trim(submit_notice.url), ''), nullif(trim(submit_notice.notifier_name), ''), nullif(trim(submit_notice.notifier_email), ''), v_me, v_trusted)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'itemId', v_row."item_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'explanation', v_row."explanation", 'url', v_row."url", 'notifierName', v_row."notifier_name", 'notifierEmail', v_row."notifier_email", 'notifierId', v_row."notifier_id", 'trusted', v_row."trusted", 'status', v_row."status", 'outcome', v_row."outcome", 'decidedBy', v_row."decided_by", 'decidedAt', v_row."decided_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."submit_notice"(uuid, text, text, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."submit_notice"(uuid, text, text, text, text, text, text) to authenticated, service_role;

-- The notices of an organization, trusted flaggers first, then oldest first.
-- Without a status it lists the notices that wait for a decision.
create or replace function "better_supabase"."list_notices"(tenant uuid, status text default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_notices.tenant, 'moderation.read'), false)) then
    raise exception 'not allowed to read notices' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.notice order by q.trusted desc, q.created asc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'itemId', x."item_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'explanation', x."explanation", 'url', x."url", 'notifierName', x."notifier_name", 'notifierEmail', x."notifier_email", 'notifierId', x."notifier_id", 'trusted', x."trusted", 'status', x."status", 'outcome', x."outcome", 'decidedBy', x."decided_by", 'decidedAt', x."decided_at", 'createdAt', x."created_at") as notice, x."trusted" as trusted, x."created_at" as created
    from "better_supabase"."moderation_notices" x
    where x."tenant_id" = list_notices.tenant
      and x."status" = coalesce(list_notices.status, 'received')
    order by x."trusted" desc, x."created_at" asc
    limit least(greatest(coalesce(list_notices.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_notices"(uuid, text, integer) from public, anon;
grant execute on function "better_supabase"."list_notices"(uuid, text, integer) to authenticated, service_role;

-- Decides a notice: hide or remove the content, or reject the notice. The
-- notifier is told through the moderation_notice.decided event.
create or replace function "better_supabase"."decide_notice"(notice_id uuid, decision text, outcome text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."moderation_notices";
  v_item "better_supabase"."moderation_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."moderation_notices" x where x."id" = decide_notice.notice_id for update;
  if v_row."id" is null then
    raise exception 'notice not found' using errcode = 'P0002', hint = 'MODERATION_NOTICE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'moderation.manage'), false)) then
    raise exception 'not allowed to decide on notices' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if decide_notice.decision is null or decide_notice.decision not in ('hide', 'remove', 'reject') then
    raise exception 'decision must be hide, remove or reject' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if length(decide_notice.outcome) > 2000 then
    raise exception 'outcome must be at most 2000 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if v_row."status" <> 'received' then
    raise exception 'this notice was decided already' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if decide_notice.decision <> 'reject' then
    if v_row."item_id" is null then
      raise exception 'moderation item not found' using errcode = 'P0002', hint = 'MODERATION_ITEM_NOT_FOUND';
    end if;
    perform "better_supabase"."moderation_apply"(v_row."item_id", decide_notice.decision, decide_notice.outcome, false);
  end if;
  update "better_supabase"."moderation_notices" x
  set "status" = case when decide_notice.decision = 'reject' then 'rejected' else 'actioned' end,
    "outcome" = nullif(trim(decide_notice.outcome), ''), "decided_by" = auth.uid(), "decided_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'itemId', v_row."item_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'explanation', v_row."explanation", 'url', v_row."url", 'notifierName', v_row."notifier_name", 'notifierEmail', v_row."notifier_email", 'notifierId', v_row."notifier_id", 'trusted', v_row."trusted", 'status', v_row."status", 'outcome', v_row."outcome", 'decidedBy', v_row."decided_by", 'decidedAt', v_row."decided_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."decide_notice"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."decide_notice"(uuid, text, text) to authenticated, service_role;

-- Records a statement of reasons (DSA Article 17) for an item a moderator
-- restricted. A statement names the legal ground, the terms ground or both.
create or replace function "better_supabase"."issue_statement"(item_id uuid, restriction text, facts text, legal_ground text default null, terms_ground text default null, automated_detection boolean default false, automated_decision boolean default false, redress text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item "better_supabase"."moderation_items";
  v_row "better_supabase"."moderation_statements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_item from "better_supabase"."moderation_items" x where x."id" = issue_statement.item_id;
  if v_item."id" is null then
    raise exception 'moderation item not found' using errcode = 'P0002', hint = 'MODERATION_ITEM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_item."tenant_id", 'moderation.manage'), false)) then
    raise exception 'not allowed to issue statements of reasons' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if issue_statement.restriction is null or issue_statement.restriction not in ('removal', 'disabled_access', 'demotion', 'visibility_suspension', 'monetary_suspension', 'service_suspension', 'service_termination', 'account_suspension', 'account_termination') then
    raise exception 'restriction must be one of the Article 17 restrictions' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if issue_statement.facts is null or length(trim(issue_statement.facts)) = 0 or length(issue_statement.facts) > 5000 then
    raise exception 'a statement needs facts and circumstances of at most 5000 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if nullif(trim(issue_statement.legal_ground), '') is null and nullif(trim(issue_statement.terms_ground), '') is null then
    raise exception 'a statement needs a legal ground or a terms ground' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  insert into "better_supabase"."moderation_statements" ("tenant_id", "item_id", "restriction", "facts", "legal_ground", "terms_ground", "automated_detection", "automated_decision", "redress", "issued_by")
  values (v_item."tenant_id", v_item."id", issue_statement.restriction, trim(issue_statement.facts), nullif(trim(issue_statement.legal_ground), ''), nullif(trim(issue_statement.terms_ground), ''),
    coalesce(issue_statement.automated_detection, false), coalesce(issue_statement.automated_decision, false),
    coalesce(issue_statement.redress, array['internal_complaint', 'out_of_court', 'judicial']), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'itemId', v_row."item_id", 'restriction', v_row."restriction", 'facts', v_row."facts", 'legalGround', v_row."legal_ground", 'termsGround', v_row."terms_ground", 'automatedDetection', v_row."automated_detection", 'automatedDecision', v_row."automated_decision", 'redress', to_jsonb(v_row."redress"), 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."issue_statement"(uuid, text, text, text, text, boolean, boolean, text[]) from public, anon;
grant execute on function "better_supabase"."issue_statement"(uuid, text, text, text, text, boolean, boolean, text[]) to authenticated, service_role;

-- The statements of reasons for one item, newest first. The item's author
-- reads their own through the same call.
create or replace function "better_supabase"."list_statements"(item_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item "better_supabase"."moderation_items";
begin
  select * into v_item from "better_supabase"."moderation_items" x where x."id" = list_statements.item_id;
  if v_item."id" is null then
    raise exception 'moderation item not found' using errcode = 'P0002', hint = 'MODERATION_ITEM_NOT_FOUND';
  end if;
  if not ((auth.uid() is not null and v_item."author_id" is not distinct from auth.uid()) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_item."tenant_id", 'moderation.read'), false))) then
    raise exception 'not allowed to read statements of reasons' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'itemId', y."item_id", 'restriction', y."restriction", 'facts', y."facts", 'legalGround', y."legal_ground", 'termsGround', y."terms_ground", 'automatedDetection', y."automated_detection", 'automatedDecision', y."automated_decision", 'redress', to_jsonb(y."redress"), 'issuedBy', y."issued_by", 'createdAt', y."created_at") order by y."created_at" desc) from "better_supabase"."moderation_statements" y where y."item_id" = v_item."id"), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_statements"(uuid) from public, anon;
grant execute on function "better_supabase"."list_statements"(uuid) to authenticated, service_role;

-- Awards or revokes trusted flagger status (DSA Article 22) for a user.
create or replace function "better_supabase"."set_trusted_flagger"(tenant uuid, user_id uuid, name text default null, awarded_by text default null, active boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."moderation_flaggers";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_trusted_flagger.tenant, 'moderation.manage'), false)) then
    raise exception 'not allowed to manage trusted flaggers' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if set_trusted_flagger.active is false then
    update "better_supabase"."moderation_flaggers" x set "revoked_at" = now()
    where x."tenant_id" = set_trusted_flagger.tenant and x."user_id" = set_trusted_flagger.user_id and x."revoked_at" is null
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'no active trusted flagger for this user' using errcode = 'P0002', hint = 'MODERATION_FLAGGER_NOT_FOUND';
    end if;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'name', v_row."name", 'awardedBy', v_row."awarded_by", 'revokedAt', v_row."revoked_at", 'createdAt', v_row."created_at");
  end if;
  if set_trusted_flagger.name is null or length(trim(set_trusted_flagger.name)) not between 1 and 200 then
    raise exception 'a trusted flagger needs a name of at most 200 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  select * into v_row from "better_supabase"."moderation_flaggers" x
  where x."tenant_id" = set_trusted_flagger.tenant and x."user_id" = set_trusted_flagger.user_id and x."revoked_at" is null;
  if v_row."id" is null then
    insert into "better_supabase"."moderation_flaggers" ("tenant_id", "user_id", "name", "awarded_by")
    values (set_trusted_flagger.tenant, set_trusted_flagger.user_id, trim(set_trusted_flagger.name), nullif(trim(set_trusted_flagger.awarded_by), ''))
    returning * into v_row;
  else
    update "better_supabase"."moderation_flaggers" x
    set "name" = trim(set_trusted_flagger.name), "awarded_by" = nullif(trim(set_trusted_flagger.awarded_by), '')
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'name', v_row."name", 'awardedBy', v_row."awarded_by", 'revokedAt', v_row."revoked_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."set_trusted_flagger"(uuid, uuid, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."set_trusted_flagger"(uuid, uuid, text, text, boolean) to authenticated, service_role;

-- Files an appeal (DSA Article 20) against a statement of reasons, or against
-- a rejected notice. Only the affected content's author or the notifier can.
create or replace function "better_supabase"."file_appeal"(statement_id uuid default null, notice_id uuid default null, reasons text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant uuid;
  v_row "better_supabase"."moderation_appeals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to file an appeal' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if (file_appeal.statement_id is null) = (file_appeal.notice_id is null) then
    raise exception 'an appeal names a statement or a notice' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if file_appeal.reasons is null or length(trim(file_appeal.reasons)) = 0 or length(file_appeal.reasons) > 5000 then
    raise exception 'an appeal needs reasons of at most 5000 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if file_appeal.statement_id is not null then
    select s."tenant_id" into v_tenant
    from "better_supabase"."moderation_statements" s join "better_supabase"."moderation_items" x on x."id" = s."item_id"
    where s."id" = file_appeal.statement_id and x."author_id" = v_me;
  else
    select x."tenant_id" into v_tenant from "better_supabase"."moderation_notices" x
    where x."id" = file_appeal.notice_id and x."notifier_id" = v_me and x."status" = 'rejected';
  end if;
  if v_tenant is null then
    raise exception 'you can only appeal a decision that affects you' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  begin
    insert into "better_supabase"."moderation_appeals" ("tenant_id", "statement_id", "notice_id", "appellant_id", "reasons")
    values (v_tenant, file_appeal.statement_id, file_appeal.notice_id, v_me, trim(file_appeal.reasons))
    returning * into v_row;
  exception when unique_violation then
    raise exception 'an appeal is open for this decision already' using errcode = '22023', hint = 'MODERATION_INVALID';
  end;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'statementId', v_row."statement_id", 'noticeId', v_row."notice_id", 'appellantId', v_row."appellant_id", 'reasons', v_row."reasons", 'status', v_row."status", 'outcome', v_row."outcome", 'decidedBy', v_row."decided_by", 'decidedAt', v_row."decided_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."file_appeal"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."file_appeal"(uuid, uuid, text) to authenticated, service_role;

-- Decides an appeal. The decision needs a person, not an automated means
-- (DSA Article 20(6)). Reversing an appeal against a statement restores the
-- content; reversing one against a notice puts the notice back in the queue.
create or replace function "better_supabase"."decide_appeal"(appeal_id uuid, outcome text, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."moderation_appeals";
  v_item "better_supabase"."moderation_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."moderation_appeals" x where x."id" = decide_appeal.appeal_id for update;
  if v_row."id" is null then
    raise exception 'appeal not found' using errcode = 'P0002', hint = 'MODERATION_APPEAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'moderation.manage'), false)) then
    raise exception 'not allowed to decide on appeals' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if decide_appeal.outcome is null or decide_appeal.outcome not in ('upheld', 'reversed') then
    raise exception 'outcome must be upheld or reversed' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if length(decide_appeal.reason) > 2000 then
    raise exception 'reason must be at most 2000 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'this appeal was decided already' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if decide_appeal.outcome = 'reversed' then
    if v_row."statement_id" is not null then
      select x.* into v_item from "better_supabase"."moderation_items" x join "better_supabase"."moderation_statements" s on s."item_id" = x."id" where s."id" = v_row."statement_id";
      if v_item."status" in ('hidden', 'removed') then
        perform "better_supabase"."moderation_apply"(v_item."id", 'restore', decide_appeal.reason, false);
      end if;
    else
      update "better_supabase"."moderation_notices" x set "status" = 'received', "decided_at" = null, "decided_by" = null
      where x."id" = v_row."notice_id";
    end if;
  end if;
  update "better_supabase"."moderation_appeals" x
  set "status" = decide_appeal.outcome, "outcome" = nullif(trim(decide_appeal.reason), ''), "decided_by" = auth.uid(), "decided_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'statementId', v_row."statement_id", 'noticeId', v_row."notice_id", 'appellantId', v_row."appellant_id", 'reasons', v_row."reasons", 'status', v_row."status", 'outcome', v_row."outcome", 'decidedBy', v_row."decided_by", 'decidedAt', v_row."decided_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."decide_appeal"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."decide_appeal"(uuid, text, text) to authenticated, service_role;

-- The transparency report (DSA Articles 15 and 24) for a period, as CSV with
-- the columns metric, dimension and value: notices by status and from trusted
-- flaggers, statements by restriction and automated means, appeals by
-- outcome, and moderation decisions by action.
create or replace function "better_supabase"."transparency_report"(tenant uuid, period_start timestamptz, period_end timestamptz)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_csv text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', transparency_report.tenant, 'moderation.read'), false)) then
    raise exception 'not allowed to read the transparency report' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if transparency_report.period_start is null or transparency_report.period_end is null or transparency_report.period_end <= transparency_report.period_start then
    raise exception 'the period needs a start before its end' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  with rows (metric, dimension, value, sort) as (
    select 'notices', 'received', count(*), 10 from "better_supabase"."moderation_notices" x
    where x."tenant_id" = transparency_report.tenant and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    union all
    select 'notices', 'trusted_flagger', count(*), 11 from "better_supabase"."moderation_notices" x
    where x."tenant_id" = transparency_report.tenant and x."trusted" and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    union all
    select 'notices', x."status", count(*), 12 from "better_supabase"."moderation_notices" x
    where x."tenant_id" = transparency_report.tenant and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    group by x."status"
    union all
    select 'statements', x."restriction", count(*), 20 from "better_supabase"."moderation_statements" x
    where x."tenant_id" = transparency_report.tenant and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    group by x."restriction"
    union all
    select 'statements', 'automated_detection', count(*), 21 from "better_supabase"."moderation_statements" x
    where x."tenant_id" = transparency_report.tenant and x."automated_detection" and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    union all
    select 'statements', 'automated_decision', count(*), 22 from "better_supabase"."moderation_statements" x
    where x."tenant_id" = transparency_report.tenant and x."automated_decision" and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    union all
    select 'appeals', 'received', count(*), 30 from "better_supabase"."moderation_appeals" x
    where x."tenant_id" = transparency_report.tenant and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    union all
    select 'appeals', x."status", count(*), 31 from "better_supabase"."moderation_appeals" x
    where x."tenant_id" = transparency_report.tenant and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    group by x."status"
    union all
    select 'decisions', x."action"::text, count(*), 40 from "better_supabase"."moderation_actions" x
    where x."tenant_id" = transparency_report.tenant and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
    group by x."action"
    union all
    select 'reports', 'received', count(*), 50 from "better_supabase"."moderation_reports" x
    where x."tenant_id" = transparency_report.tenant and x."created_at" >= transparency_report.period_start and x."created_at" < transparency_report.period_end
  )
  select 'metric,dimension,value' || coalesce(E'\n' || string_agg(r.metric || ',' || r.dimension || ',' || r.value::text, E'\n' order by r.sort, r.dimension), '')
  into v_csv from rows r;
  return v_csv;
end;
$$;
revoke execute on function "better_supabase"."transparency_report"(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."transparency_report"(uuid, timestamptz, timestamptz) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_workspace_ids(text[])') is null then
    create function better_supabase.member_workspace_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."moderation_items";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."moderation_items";
create policy bsb_tenant_scope_select on "better_supabase"."moderation_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."moderation_items";
create policy bsb_tenant_scope_insert on "better_supabase"."moderation_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."moderation_items";
create policy bsb_tenant_scope_update on "better_supabase"."moderation_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."moderation_items";
create policy bsb_tenant_scope_delete on "better_supabase"."moderation_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."moderation_reports";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."moderation_reports";
create policy bsb_tenant_scope_select on "better_supabase"."moderation_reports" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("reporter_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."moderation_reports";
create policy bsb_tenant_scope_insert on "better_supabase"."moderation_reports" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."moderation_reports";
create policy bsb_tenant_scope_update on "better_supabase"."moderation_reports" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."moderation_reports";
create policy bsb_tenant_scope_delete on "better_supabase"."moderation_reports" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."moderation_actions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."moderation_actions";
create policy bsb_tenant_scope_select on "better_supabase"."moderation_actions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."moderation_actions";
create policy bsb_tenant_scope_insert on "better_supabase"."moderation_actions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."moderation_actions";
create policy bsb_tenant_scope_update on "better_supabase"."moderation_actions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."moderation_actions";
create policy bsb_tenant_scope_delete on "better_supabase"."moderation_actions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."moderation_bans";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."moderation_bans";
create policy bsb_tenant_scope_select on "better_supabase"."moderation_bans" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."moderation_bans";
create policy bsb_tenant_scope_insert on "better_supabase"."moderation_bans" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."moderation_bans";
create policy bsb_tenant_scope_update on "better_supabase"."moderation_bans" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."moderation_bans";
create policy bsb_tenant_scope_delete on "better_supabase"."moderation_bans" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."moderation_statements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."moderation_statements";
create policy bsb_tenant_scope_select on "better_supabase"."moderation_statements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."moderation_statements";
create policy bsb_tenant_scope_insert on "better_supabase"."moderation_statements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."moderation_statements";
create policy bsb_tenant_scope_update on "better_supabase"."moderation_statements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."moderation_statements";
create policy bsb_tenant_scope_delete on "better_supabase"."moderation_statements" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."moderation_notices";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."moderation_notices";
create policy bsb_tenant_scope_select on "better_supabase"."moderation_notices" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("notifier_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."moderation_notices";
create policy bsb_tenant_scope_insert on "better_supabase"."moderation_notices" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."moderation_notices";
create policy bsb_tenant_scope_update on "better_supabase"."moderation_notices" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."moderation_notices";
create policy bsb_tenant_scope_delete on "better_supabase"."moderation_notices" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."moderation_flaggers";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."moderation_flaggers";
create policy bsb_tenant_scope_select on "better_supabase"."moderation_flaggers" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."moderation_flaggers";
create policy bsb_tenant_scope_insert on "better_supabase"."moderation_flaggers" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."moderation_flaggers";
create policy bsb_tenant_scope_update on "better_supabase"."moderation_flaggers" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."moderation_flaggers";
create policy bsb_tenant_scope_delete on "better_supabase"."moderation_flaggers" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."moderation_appeals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."moderation_appeals";
create policy bsb_tenant_scope_select on "better_supabase"."moderation_appeals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("appellant_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."moderation_appeals";
create policy bsb_tenant_scope_insert on "better_supabase"."moderation_appeals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."moderation_appeals";
create policy bsb_tenant_scope_update on "better_supabase"."moderation_appeals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."moderation_appeals";
create policy bsb_tenant_scope_delete on "better_supabase"."moderation_appeals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_108_moderation.sql
-- better-supabase module: moderation
-- @bsb-block-data moderation
-- @bsb-hash sha256:97d80d244d5ecfdb00b7662ae72c988dec37f9a47d1839281040f4050ac1d3b5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('moderation', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
