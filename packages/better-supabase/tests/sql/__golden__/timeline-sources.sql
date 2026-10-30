-- better-supabase module: timeline
-- @bsb-block timeline@1 managed
-- @bsb-hash sha256:618de061a6b0729d173fcf904f5a6c5109b6569603f741cc2a449a47ca6c1eec
-- An activity_entries feed that activitySink() fills from outbox events, filtered by can_subject and joined with the subject's audit entries, notification deliveries and workflow runs when subjects, audit, notifications and workflows are installed.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."activity_entries";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."activity_entries";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."activity_entries";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."activity_entries";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."activity_entries";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- The activity feed: one row per outbox event, written by activitySink().
create table if not exists "better_supabase"."activity_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "event_id" text not null unique,
  "type" text not null,
  "actor_id" uuid references auth.users (id) on delete set null,
  "subject_type" text,
  "subject_id" text,
  "summary" text,
  "data" jsonb not null default '{}'::jsonb,
  "occurred_at" timestamptz not null default now()
);
create index if not exists activity_entries_feed_idx on "better_supabase"."activity_entries" ("organization_id", "occurred_at" desc, "id" desc);
create index if not exists activity_entries_subject_idx on "better_supabase"."activity_entries" ("organization_id", "subject_type", "subject_id");
create index if not exists activity_entries_actor_idx on "better_supabase"."activity_entries" ("actor_id");
alter table "better_supabase"."activity_entries" enable row level security;
revoke all on "better_supabase"."activity_entries" from public, anon, authenticated;
grant select on "better_supabase"."activity_entries" to authenticated;
grant all on "better_supabase"."activity_entries" to service_role;
-- Whether the caller can read a registered subject (can_subject).
create or replace function "better_supabase"."activity_subject_readable"(subject_type text, subject_id text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return coalesce("better_supabase"."can_subject"(subject_type, subject_id, 'read'), false);
end;
$$;
revoke execute on function "better_supabase"."activity_subject_readable"(text, text) from public, anon;
grant execute on function "better_supabase"."activity_subject_readable"(text, text) to authenticated, service_role;
drop policy if exists activity_entries_read on "better_supabase"."activity_entries";
create policy activity_entries_read on "better_supabase"."activity_entries"
  for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('timeline.read'))
    and ("subject_type" is null or "subject_id" is null
      or not ("subject_type" = any ('{quote,note}'::text[]))
      or "better_supabase"."activity_subject_readable"("subject_type", "subject_id")));
drop function if exists "better_supabase"."activity_subject_deliveries"(uuid, text, text, timestamptz, integer);

-- Inserts batch.entries ({ event_id, organization_id, type, actor_id?,
-- subject_type?, subject_id?, summary?, data?, occurred_at? }); a seen
-- event_id is skipped, so a replayed batch writes nothing twice. The list
-- sits in an object so it reaches jsonb the same way over Postgres and the
-- Data API.
create or replace function "better_supabase"."record_activity"(batch jsonb)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  inserted integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records activity' using errcode = '42501', hint = 'TIMELINE_ENTRY_FORBIDDEN';
  end if;
  insert into "better_supabase"."activity_entries" ("event_id", "organization_id", "type", "actor_id", "subject_type", "subject_id", "summary", "data", "occurred_at")
  select e ->> 'event_id', (e ->> 'organization_id')::uuid, e ->> 'type', nullif(e ->> 'actor_id', '')::uuid,
    e ->> 'subject_type', e ->> 'subject_id', e ->> 'summary', coalesce(e -> 'data', '{}'::jsonb),
    coalesce((e ->> 'occurred_at')::timestamptz, now())
  from jsonb_array_elements(coalesce(batch -> 'entries', '[]'::jsonb)) e
  on conflict ("event_id") do nothing;
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

-- A tenant's activity, newest first, or one subject's timeline with
-- subject_type and subject_id; before pages back, and sources (null for
-- all) picks the kinds of entry. Runs as the caller, and each entry carries
-- source: event for an activity entry,
-- transition for a state-machine status change of the subject,
-- message for a message in the subject's conversation.
-- A registered subject's timeline is empty unless can_subject grants read.
create or replace function "better_supabase"."list_activity"(
  tenant uuid,
  subject_type text default null,
  subject_id text default null,
  before timestamptz default null,
  max_rows integer default 50,
  sources text[] default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(list_activity.max_rows, 50), 1), 500);
  v_rows jsonb;
begin
  if list_activity.subject_id is not null and list_activity.subject_type = any ('{quote,note}'::text[])
    and not "better_supabase"."activity_subject_readable"(list_activity.subject_type, list_activity.subject_id) then
    return '[]'::jsonb;
  end if;
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y."occurred_at" as at, y."id"::text as id
    from "better_supabase"."activity_entries" y
    where y."organization_id" = list_activity.tenant
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
      and not ((y."type" = 'status.changed' and list_activity.subject_id is not null
      and list_activity.subject_type = any ('{quote,note}'::text[])
      and list_activity.subject_type = any ('{quote}'::text[])
      and (list_activity.sources is null or 'transition' = any (list_activity.sources)))
        or (y."type" in ('message.sent', 'comment.posted') and list_activity.subject_id is not null
      and list_activity.subject_type = any ('{quote,note}'::text[])
      and (list_activity.sources is null or 'message' = any (list_activity.sources))))
    order by y."occurred_at" desc, y."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', h."id"::text, 'organization_id', h."tenant_id", 'event_id', null::text, 'type', 'status.changed', 'actor_id', h."actor_user_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', null::text, 'data', jsonb_strip_nulls(jsonb_build_object('from', h."from_status"::text, 'to', h."to_status"::text, 'reason', h."reason")), 'occurred_at', h."created_at", 'source', 'transition') as entry,
      h."created_at" as at, h."id"::text as id
    from "better_supabase"."status_history" h
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{quote,note}'::text[])
      and list_activity.subject_type = any ('{quote}'::text[])
      and (list_activity.sources is null or 'transition' = any (list_activity.sources))
      and h."tenant_id" = list_activity.tenant
      and h."subject_type" = list_activity.subject_type
      and h."subject_id" = list_activity.subject_id
      and (list_activity.before is null or h."created_at" < list_activity.before)
    order by h."created_at" desc, h."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', m."id"::text, 'organization_id', m."tenant_id", 'event_id', null::text, 'type', case when c."kind" = 'subject' then 'comment.posted' else 'message.sent' end, 'actor_id', m."author_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', left(m."body", 280), 'data', jsonb_strip_nulls(jsonb_build_object('messageId', m."id", 'conversationId', m."conversation_id", 'threadId', m."thread_id", 'kind', m."kind"::text)), 'occurred_at', m."sent_at", 'source', 'message') as entry,
      m."sent_at" as at, m."id"::text as id
    from "better_supabase"."messages" m
    join "better_supabase"."conversations" c on c."id" = m."conversation_id"
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{quote,note}'::text[])
      and (list_activity.sources is null or 'message' = any (list_activity.sources))
      and c."tenant_id" = list_activity.tenant
      and c."subject_type" = list_activity.subject_type
      and c."subject_id" = list_activity.subject_id
      and m."sent_at" is not null
      and m."deleted_at" is null
      and (list_activity.before is null or m."sent_at" < list_activity.before)
    order by m."sent_at" desc, m."id" desc
    limit v_limit)
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_activity"(uuid, text, text, timestamptz, integer, text[]) from public, anon;
revoke execute on function "better_supabase"."record_activity"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."list_activity"(uuid, text, text, timestamptz, integer, text[]) to authenticated, service_role;
grant execute on function "better_supabase"."record_activity"(jsonb) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."activity_entries";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."activity_entries";
create policy bsb_tenant_scope_select on "better_supabase"."activity_entries" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('timeline.read'))
    and ("subject_type" is null or "subject_id" is null
      or not ("subject_type" = any ('{quote,note}'::text[]))
      or "better_supabase"."activity_subject_readable"("subject_type", "subject_id")))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."activity_entries";
create policy bsb_tenant_scope_insert on "better_supabase"."activity_entries" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."activity_entries";
create policy bsb_tenant_scope_update on "better_supabase"."activity_entries" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."activity_entries";
create policy bsb_tenant_scope_delete on "better_supabase"."activity_entries" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

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

-- better-supabase module: timeline
-- @bsb-block-data timeline
-- @bsb-hash sha256:bdeeff274088237a937407908b9bca2166cd0f961749298ea2a0671967579388
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Event types renamed by the 0.47 naming convention (ADR 0130).
update "better_supabase"."activity_entries" t set "type" = m.next_type
from (values
  ('access.ended', 'access_request.ended'),
  ('access.request_approved', 'access_request.approved'),
  ('access.requested', 'access_request.requested'),
  ('ai_tool_policy.set', 'ai_tool_policy.updated'),
  ('approval_policy.removed', 'approval_policy.deleted'),
  ('compliance_policy.acknowledged', 'acknowledgement.created'),
  ('credential.set', 'credential.updated'),
  ('custom_field.deleted', 'field_definition.deleted'),
  ('drive.node_created', 'drive_node.created'),
  ('drive.node_document_saved', 'drive_node.document_saved'),
  ('drive.node_download_blocked_changed', 'drive_node.download_blocked_changed'),
  ('drive.node_hold_placed', 'drive_node.hold_placed'),
  ('drive.node_hold_released', 'drive_node.hold_released'),
  ('drive.node_locked', 'drive_node.locked'),
  ('drive.node_moved', 'drive_node.moved'),
  ('drive.node_obsoleted', 'drive_node.obsoleted'),
  ('drive.node_ownership_transferred', 'drive_node.ownership_transferred'),
  ('drive.node_purged', 'drive_node.purged'),
  ('drive.node_released', 'drive_node.released'),
  ('drive.node_renamed', 'drive_node.renamed'),
  ('drive.node_review_requested', 'drive_node.review_requested'),
  ('drive.node_reviewed', 'drive_node.reviewed'),
  ('drive.node_shared', 'drive_node.shared'),
  ('drive.node_submitted', 'drive_node.submitted'),
  ('drive.node_unlocked', 'drive_node.unlocked'),
  ('drive.node_unshared', 'drive_node.unshared'),
  ('engagement.amended', 'activity.amended'),
  ('engagement.completed', 'activity.completed'),
  ('engagement.deleted', 'activity.deleted'),
  ('engagement.error_marked', 'activity.error_marked'),
  ('engagement.logged', 'activity.logged'),
  ('engagement.recorded', 'activity.recorded'),
  ('engagement.summarized', 'activity.summarized'),
  ('engagement.transcribed', 'activity.transcribed'),
  ('engagement.updated', 'activity.updated'),
  ('flag.override_set', 'flag.override_changed'),
  ('forecast.snapshotted', 'forecast_snapshot.created'),
  ('hostname.primary_set', 'hostname.primary_changed'),
  ('hostname.removed', 'hostname.deleted'),
  ('incoming_webhook.enabled_set', 'incoming_webhook.enabled_changed'),
  ('job.closed', 'job_opening.closed'),
  ('job.opened', 'job_opening.opened'),
  ('leave.adjusted', 'leave_balance.adjusted'),
  ('leave.approved', 'leave_request.approved'),
  ('leave.cancelled', 'leave_request.cancelled'),
  ('leave.rejected', 'leave_request.rejected'),
  ('leave.requested', 'leave_request.requested'),
  ('leave.split', 'leave_request.split'),
  ('leave.updated', 'leave_request.updated'),
  ('marketplace_installation.removed', 'marketplace_installation.deleted'),
  ('marketplace_invoice.state_changed', 'marketplace_invoice.status_changed'),
  ('obligation.status_changed', 'contract_obligation.status_changed'),
  ('organization.domain_added', 'sso_domain.created'),
  ('organization.domain_removed', 'sso_domain.deleted'),
  ('organization.domain_updated', 'sso_domain.updated'),
  ('organization.domain_verified', 'sso_domain.verified'),
  ('policy.acknowledged', 'acknowledgement.created'),
  ('policy.published', 'compliance_policy.published'),
  ('postmortem.published', 'incident_postmortem.published'),
  ('rule.disabled', 'automation.disabled'),
  ('rule.enabled', 'automation.enabled'),
  ('rule.matched', 'automation.matched'),
  ('rule.removed', 'automation.deleted'),
  ('segment.removed', 'segment.deleted'),
  ('signature.cancelled', 'signature_request.cancelled'),
  ('signature.completed', 'signature_request.completed'),
  ('signature.declined', 'signature_request.declined'),
  ('signature.requested', 'signature_request.requested'),
  ('signature.signed', 'signature_request.signed'),
  ('support.denied', 'support_session.denied'),
  ('support.ended', 'support_session.ended'),
  ('support.started', 'support_session.started'),
  ('time.invoiced', 'time_entry.invoiced'),
  ('variant.created', 'product_variant.created'),
  ('variant.deleted', 'product_variant.deleted'),
  ('variant.updated', 'product_variant.updated'),
  ('waitlist.approved', 'waitlist_entry.approved'),
  ('waitlist.rejected', 'waitlist_entry.rejected'),
  ('webhook.delivered', 'webhook_endpoint.delivered'),
  ('webhook.disabled', 'webhook_endpoint.disabled'),
  ('webhook.failed', 'webhook_endpoint.failed'),
  ('webhook.secret_rotated', 'webhook_endpoint.secret_rotated'),
  ('work_item.archived', 'task.archived'),
  ('work_item.assigned', 'task.assigned'),
  ('work_item.closed', 'task.closed'),
  ('work_item.created', 'task.created'),
  ('work_item.deleted', 'task.deleted'),
  ('work_item.reopened', 'task.reopened'),
  ('work_item.updated', 'task.updated'),
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."type" = m.old_type;

insert into better_supabase.blocks (name, version, mode)
values ('timeline', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
