-- better-supabase module: moderation
-- @bsb-block moderation@1 managed
-- Reports on any subject, a review queue, decisions (approve, hide, remove, restore, ban) with a log, user bans and an automatic hide threshold. Reviews moderate through it, and it hides and removes messages, comments included.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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

alter table "better_supabase"."moderation_items" enable row level security;
revoke all on "better_supabase"."moderation_items" from anon, authenticated;
grant select on "better_supabase"."moderation_items" to authenticated;
grant all on "better_supabase"."moderation_items" to service_role;
drop policy if exists "moderation_items_read" on "better_supabase"."moderation_items";
create policy "moderation_items_read" on "better_supabase"."moderation_items" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')));
alter table "better_supabase"."moderation_reports" enable row level security;
revoke all on "better_supabase"."moderation_reports" from anon, authenticated;
grant select on "better_supabase"."moderation_reports" to authenticated;
grant all on "better_supabase"."moderation_reports" to service_role;
drop policy if exists "moderation_reports_read" on "better_supabase"."moderation_reports";
create policy "moderation_reports_read" on "better_supabase"."moderation_reports" for select to authenticated
  using ("reporter_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')));
alter table "better_supabase"."moderation_actions" enable row level security;
revoke all on "better_supabase"."moderation_actions" from anon, authenticated;
grant select on "better_supabase"."moderation_actions" to authenticated;
grant all on "better_supabase"."moderation_actions" to service_role;
drop policy if exists "moderation_actions_read" on "better_supabase"."moderation_actions";
create policy "moderation_actions_read" on "better_supabase"."moderation_actions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')));
alter table "better_supabase"."moderation_bans" enable row level security;
revoke all on "better_supabase"."moderation_bans" from anon, authenticated;
grant select on "better_supabase"."moderation_bans" to authenticated;
grant all on "better_supabase"."moderation_bans" to service_role;
drop policy if exists "moderation_bans_read" on "better_supabase"."moderation_bans";
create policy "moderation_bans_read" on "better_supabase"."moderation_bans" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('moderation.read')));

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
  if moderation_apply.action = 'restore' and v_old."status" = 'removed' and v_old."subject_type" = 'message' then
    raise exception 'a removed message can''t be restored' using errcode = '22023', hint = 'MODERATION_INVALID';
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
  if v_row."subject_type" = 'message' and v_status = 'removed' then
    update "better_supabase"."messages" x
    set "body" = '', "document" = null, "mentions" = '{}', "mention_scope" = null,
      "pinned_at" = null, "pinned_by" = null, "deleted_at" = now()
    where x."id"::text = v_row."subject_id" and x."deleted_at" is null;
  end if;
  if moderation_apply.action = 'ban' and not "better_supabase"."moderation_banned"(v_row."tenant_id", v_row."author_id") then
    delete from "better_supabase"."moderation_bans" x where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."author_id" and x."lifted_at" is null;
    insert into "better_supabase"."moderation_bans" ("tenant_id", "user_id", "reason", "banned_by")
    values (v_row."tenant_id", v_row."author_id", nullif(trim(moderation_apply.reason), ''), auth.uid())
    returning * into v_ban;
    perform "better_supabase".emit_event('moderation_ban.created', jsonb_build_object('organizationId', v_ban."tenant_id", 'id', v_ban."id", 'userId', v_ban."user_id", 'expiresAt', v_ban."expires_at"), 'moderation-bans/' || v_ban."id"::text, (v_ban."tenant_id")::text, null, 'better-supabase/moderation');
  perform better_supabase.audit_event(
    event_type => 'moderation_ban.created',
    category => 'security',
    target_type => 'user',
    record_id => v_ban."user_id"::text,
    summary => 'banned a user',
    tenant => (v_ban."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ban."tenant_id", 'id', v_ban."id", 'userId', v_ban."user_id", 'expiresAt', v_ban."expires_at")
  );
  end if;
  perform "better_supabase".emit_event('moderation_item.decided', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'action', moderation_apply.action, 'status', v_status, 'previousStatus', v_old."status", 'automatic', moderation_apply.automatic), 'moderation-items/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/moderation');
  perform better_supabase.audit_event(
    event_type => 'moderation_item.decided',
    category => 'data',
    target_type => 'moderation_item',
    record_id => v_row."id"::text,
    target_label => v_row."subject_type" || '/' || v_row."subject_id",
    summary => 'moderation: ' || moderation_apply.action,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'action', moderation_apply.action, 'status', v_status, 'previousStatus', v_old."status", 'automatic', moderation_apply.automatic)
  );
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
  if report_content.subject_type = 'message' then
    select x."author_id" into v_author from "better_supabase"."messages" x
    where x."id"::text = report_content.subject_id and x."tenant_id" = report_content.tenant and x."deleted_at" is null;
    if not found then
      raise exception 'there is no such message to report' using errcode = 'P0002', hint = 'MODERATION_SUBJECT_NOT_FOUND';
    end if;
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
  perform "better_supabase".emit_event('moderation_report.created', jsonb_build_object('organizationId', v_item."tenant_id", 'id', v_report."id", 'itemId', v_item."id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'reason', v_report."reason"), 'moderation-reports/' || v_report."id"::text, (v_item."tenant_id")::text, null, 'better-supabase/moderation');
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
  perform "better_supabase".emit_event('moderation_ban.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'expiresAt', v_row."expires_at"), 'moderation-bans/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/moderation');
  perform better_supabase.audit_event(
    event_type => 'moderation_ban.created',
    category => 'security',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    summary => 'banned a user',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'expiresAt', v_row."expires_at")
  );
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
  perform "better_supabase".emit_event('moderation_ban.lifted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'expiresAt', v_row."expires_at"), 'moderation-bans/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/moderation');
  perform better_supabase.audit_event(
    event_type => 'moderation_ban.lifted',
    category => 'security',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    summary => 'lifted a ban',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'expiresAt', v_row."expires_at")
  );
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

-- Whether a moderator hid, removed or holds back a subject. Security definer
-- so read policies can ask without reading the moderation tables.
create or replace function "better_supabase"."moderation_hidden"(subject_type text, subject_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."moderation_items" m
    where m."subject_type" = moderation_hidden.subject_type and m."subject_id" = moderation_hidden.subject_id and m."status" <> 'visible'
  )
$$;
revoke execute on function "better_supabase"."moderation_hidden"(text, text) from public, anon;
grant execute on function "better_supabase"."moderation_hidden"(text, text) to authenticated, service_role;

-- blocks.moderation.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."report_content"(tenant uuid, subject_type text, subject_id text, reason text, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."report_content"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."report_content"(uuid, text, text, text, text) from public, anon;
grant execute on function "api"."report_content"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "api"."moderate"(item_id uuid, action text, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."moderate"($1, $2, $3) $$;
revoke execute on function "api"."moderate"(uuid, text, text) from public, anon;
grant execute on function "api"."moderate"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."moderation_queue"(tenant uuid, status text default null, subject_type text default null, page_size integer default 50, before timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."moderation_queue"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."moderation_queue"(uuid, text, text, integer, timestamptz) from public, anon;
grant execute on function "api"."moderation_queue"(uuid, text, text, integer, timestamptz) to authenticated, service_role;

create or replace function "api"."moderation_item"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."moderation_item"($1, $2, $3) $$;
revoke execute on function "api"."moderation_item"(uuid, text, text) from public, anon;
grant execute on function "api"."moderation_item"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."moderation_statuses"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."moderation_statuses"($1, $2, $3) $$;
revoke execute on function "api"."moderation_statuses"(uuid, text, text[]) from public, anon;
grant execute on function "api"."moderation_statuses"(uuid, text, text[]) to authenticated, service_role;

create or replace function "api"."ban_user"(tenant uuid, user_id uuid, reason text default null, expires_at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ban_user"($1, $2, $3, $4) $$;
revoke execute on function "api"."ban_user"(uuid, uuid, text, timestamptz) from public, anon;
grant execute on function "api"."ban_user"(uuid, uuid, text, timestamptz) to authenticated, service_role;

create or replace function "api"."unban_user"(ban_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."unban_user"($1) $$;
revoke execute on function "api"."unban_user"(uuid) from public, anon;
grant execute on function "api"."unban_user"(uuid) to authenticated, service_role;

create or replace function "api"."list_bans"(tenant uuid, active boolean default true, page_size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_bans"($1, $2, $3) $$;
revoke execute on function "api"."list_bans"(uuid, boolean, integer) from public, anon;
grant execute on function "api"."list_bans"(uuid, boolean, integer) to authenticated, service_role;

create or replace function "api"."moderation_hidden"(subject_type text, subject_id text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."moderation_hidden"($1, $2) $$;
revoke execute on function "api"."moderation_hidden"(text, text) from public, anon;
grant execute on function "api"."moderation_hidden"(text, text) to authenticated, service_role;

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
