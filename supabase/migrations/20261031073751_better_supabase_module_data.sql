-- better-supabase add --adopt: the rows and settings of updated-at, audit, memberships, invitations, queue, realtime-tables, jsonb-schemas, grants, read-sets, entitlements, rate-limit, vector-search, permissions, organizations, profiles, outbox, notifications, webhooks-out, sessions, api-keys, settings, usage, flags, drive, guests, comments, attachments, data-lifecycle, sso, enrollments, onboarding, waitlist, announcements, streams, credentials, workflows, workflow-sdk, workflow-editor, chat-sdk-state, inbox, ai-chat, ai-files, knowledge, memory, agents, connectors, ai-schedules, push, ai-cache, ai-keys, numbering, teams, tags, state-machine, custom-fields, share-links, reminders, imports, subjects, rank, saved-views, relations, bulk, catalog, search, metrics, calendar, bookings, versions, trash, reactions, approvals, access-requests, documents, ledger, inventory, drive-files, orders, promotions, forms, signatures, time-tracking, service-accounts, templates, cases, deals, hiring, tasks, tasks, pipelines, contacts, activities, quotes, invoices, sla, goals, employees, signing-keys, moderation, automations, assets, scores, passes, billable-time, leases, expenses, donations, dispatch, shipments, contracts, compliance, incidents, courses, messaging, channels, timeline, mail-sync, segments, assignment, enrichment, forecasts, field-history, sequences, lead-scoring, posts, field-encryption, content, qualifications, risks, shifts, accounting, acknowledgements, consents, observations, medications, care-plans, inspections, manufacturing, banking, meetings, legal-entities, funding, which a schema diff skips.

set lock_timeout = '5s';

-- better-supabase module: updated-at
-- @bsb-block-data updated-at
-- @bsb-hash sha256:84094775e5aab9b1aea2ef256dc00640287eef63d140730c3c6c0e5390fcee95
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('updated-at', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: audit
-- @bsb-block-data audit
-- @bsb-hash sha256:1281b44af207c58632eac0ed74435a3060fa43302c307d4295e2bd74e4bf2076
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

drop event trigger if exists bsb_audit_forget_dropped;
create event trigger bsb_audit_forget_dropped on sql_drop
  when tag in ('DROP TABLE', 'DROP SCHEMA')
  execute function better_supabase.audit_forget_dropped();

-- Registrations of tables dropped before bsb_audit_forget_dropped existed.
delete from "better_supabase"."audited_tables" a
where not exists (select 1 from pg_catalog.pg_class c where c.oid = a."target"::oid);

insert into better_supabase.blocks (name, version, mode)
values ('audit', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: memberships
-- @bsb-block-data memberships
-- @bsb-hash sha256:0820ad92b94361500e57ffda4d2de42e2213687cbbe32e5f1981b88983f689fa
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('memberships', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: invitations
-- @bsb-block-data invitations
-- @bsb-hash sha256:af5820c76152303a41d469d66eed44a659f4e2f38ee513d3d7f862a9a7932c8c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('invitations', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: queue
-- @bsb-block-data queue
-- @bsb-hash sha256:dcd7bb078753ee7dd3276c0c87b29634e8e5c18459ff6c87c4895207e5526ee2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgmq";

-- Indexes the queues that existed before the module.
select better_supabase.index_job_queue(q.queue_name) from pgmq.list_queues() q;

insert into better_supabase.blocks (name, version, mode)
values ('queue', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: realtime-tables
-- @bsb-block-data realtime-tables
-- @bsb-hash sha256:3b77f16dda58cdfbf3bba8ef718621e4a7773c5e943f52e4406ff2c1cbae5f10
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('realtime-tables', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: jsonb-schemas
-- @bsb-block-data jsonb-schemas
-- @bsb-hash sha256:5731222167a8cd73a46980c1e5a175b3e562af01da2ae571aa9e76477c2cf2f2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pg_jsonschema" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('jsonb-schemas', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: grants
-- @bsb-block-data grants
-- @bsb-hash sha256:0ba55323e7817c5de5e92708f94298e2bd72c705930cd43976ed48b1cad04b56
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('grants', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: read-sets
-- @bsb-block-data read-sets
-- @bsb-hash sha256:cbe76449f0541f4dc02eb3beff22bed35fd2cd2466c6a1218218bd80a217374e
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('read-sets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: entitlements
-- @bsb-block-data entitlements
-- @bsb-hash sha256:0fe1d3ec510c4179203a9a582961bbe8876a78180dc540ca081225cb66f1fe80
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('entitlements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: rate-limit
-- @bsb-block-data rate-limit
-- @bsb-hash sha256:15898458bc504e8d36285d83cc2c6a240321839e73d4a58c113b49c3b93d8212
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Points PostgREST's pre-request hook at check_request. It keeps an
-- existing pre-request function; chain from it.
do $$
declare
  current_hook text;
begin
  select split_part(setting, '=', 2) into current_hook
  from pg_catalog.pg_db_role_setting s
  join pg_catalog.pg_roles r on r.oid = s.setrole
  cross join lateral unnest(s.setconfig) setting
  where r.rolname = 'authenticator' and s.setdatabase = 0 and setting like 'pgrst.db_pre_request=%';
  if current_hook is null then
    alter role authenticator set pgrst.db_pre_request = 'better_supabase.check_request';
  elsif current_hook <> 'better_supabase.check_request' then
    raise notice 'pgrst.db_pre_request is %; call better_supabase.check_request() from it', current_hook;
  end if;
end
$$;
notify pgrst, 'reload config';

insert into better_supabase.blocks (name, version, mode)
values ('rate-limit', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: vector-search
-- @bsb-block-data vector-search
-- @bsb-hash sha256:15bcd3e4697c3d3971a1772eb370c20551445b3f2de88d28791038c1e3e5987a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "vector" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('vector-search', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: permissions
-- @bsb-block-data permissions
-- @bsb-hash sha256:6604cde1c8de5f209d18061bf26e3965028560b862bec9c6ef42e3d8af5b059f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Permission keys renamed by the 0.46 naming convention (ADR 0130).
do $$
declare
  r record;
  v_key text;
  v_old uuid;
  v_new uuid;
  v_changed boolean := false;
begin
  for r in
    select * from (values
    ('activity.*', array['timeline.*']::text[], true),
    ('activity.read', array['timeline.read']::text[], true),
    ('ai.*', array['agents.*', 'ai_files.*', 'ai_keys.*', 'ai_schedules.*', 'connectors.*', 'knowledge.*', 'memory.*']::text[], true),
    ('ai.admin', array['ai_files.manage', 'ai_keys.manage', 'ai_schedules.manage', 'connectors.manage', 'knowledge.manage', 'memory.manage']::text[], true),
    ('ai.create', array['agents.write', 'ai_files.upload', 'ai_keys.use', 'ai_schedules.write', 'connectors.use', 'knowledge.write']::text[], true),
    ('ai.moderate', array['agents.moderate']::text[], true),
    ('ai.read', array['agents.read', 'connectors.read', 'knowledge.read', 'memory.read']::text[], true),
    ('ai.share', array['agents.publish']::text[], true),
    ('ai_chat.admin', array['ai_chat.manage']::text[], true),
    ('compliance.acknowledge', array['acknowledgements.acknowledge']::text[], true),
    ('controls.*', array['compliance.*']::text[], true),
    ('controls.acknowledge', array['acknowledgements.acknowledge']::text[], true),
    ('controls.collect', array['compliance.collect']::text[], true),
    ('controls.manage', array['compliance.manage']::text[], true),
    ('controls.read', array['compliance.read']::text[], true),
    ('custom_fields.sensitive.read', array['custom_fields.read_sensitive']::text[], true),
    ('employees.view_sensitive', array['employees.read_sensitive']::text[], true),
    ('engagements.*', array['activities.*']::text[], true),
    ('engagements.manage', array['activities.manage']::text[], true),
    ('engagements.read', array['activities.read']::text[], true),
    ('engagements.write', array['activities.write']::text[], true),
    ('history.*', array['field_history.*']::text[], true),
    ('history.read', array['field_history.read']::text[], true),
    ('mail.*', array['mail_sync.*']::text[], true),
    ('mail.connect', array['mail_sync.connect']::text[], true),
    ('mail.manage', array['mail_sync.manage']::text[], true),
    ('mail.read', array['mail_sync.read']::text[], true),
    ('mail.send', array['mail_sync.send']::text[], true),
    ('members.*', array['waitlist.invite']::text[], false),
    ('members.invite', array['waitlist.invite']::text[], false),
    ('number_sequences.*', array['numbering.*']::text[], true),
    ('number_sequences.assign', array['numbering.assign']::text[], true),
    ('organization.*', array['data_lifecycle.*']::text[], false),
    ('organization.export', array['data_lifecycle.export']::text[], true),
    ('parties.*', array['contacts.*']::text[], true),
    ('parties.manage', array['contacts.manage']::text[], true),
    ('parties.read', array['contacts.read']::text[], true),
    ('parties.write', array['contacts.write']::text[], true),
    ('rules.*', array['automations.*']::text[], true),
    ('rules.admin', array['automations.manage']::text[], true),
    ('rules.edit', array['automations.write']::text[], true),
    ('rules.publish', array['automations.publish']::text[], true),
    ('rules.read', array['automations.read']::text[], true),
    ('segments.edit', array['segments.write']::text[], true),
    ('service_principals.*', array['service_accounts.*']::text[], true),
    ('service_principals.manage', array['service_accounts.manage']::text[], true),
    ('service_principals.read', array['service_accounts.read']::text[], true),
    ('support.*', array['impersonation.*']::text[], true),
    ('support.read', array['impersonation.read']::text[], true),
    ('support.revoke', array['impersonation.revoke']::text[], true),
    ('support.start', array['impersonation.start']::text[], true),
    ('targets.*', array['goals.*']::text[], true),
    ('targets.manage', array['goals.manage']::text[], true),
    ('targets.read', array['goals.read']::text[], true),
    ('views.*', array['saved_views.*']::text[], true),
    ('views.read', array['saved_views.read']::text[], true),
    ('views.share', array['saved_views.share']::text[], true),
    ('work_items.*', array['tasks.*']::text[], true),
    ('work_items.manage', array['tasks.manage']::text[], true),
    ('work_items.read', array['tasks.read']::text[], true),
    ('work_items.write', array['tasks.write']::text[], true),
    ('workflow.*', array['workflows.*', 'workflow_editor.*']::text[], true),
    ('workflow.admin', array['workflows.manage', 'workflow_editor.manage']::text[], true),
    ('workflow.edit', array['workflow_editor.write']::text[], true),
    ('workflow.publish', array['workflow_editor.publish']::text[], true),
    ('workflow.read', array['workflows.read', 'workflow_editor.read']::text[], true),
    ('workflow.run', array['workflows.run', 'workflow_editor.run']::text[], true)
    ) as m(old_key, next_keys, retire)
  loop
    select "id" into v_old from "better_supabase"."permissions" where "key" = r.old_key;
    continue when v_old is null;
    v_changed := true;

    if r.retire and cardinality(r.next_keys) = 1
      and not exists (select 1 from "better_supabase"."permissions" where "key" = r.next_keys[1]) then
      update "better_supabase"."permissions" set "key" = r.next_keys[1] where "id" = v_old;
      continue;
    end if;

    foreach v_key in array r.next_keys loop
      select "id" into v_new from "better_supabase"."permissions" where "key" = v_key;
      if v_new is null then
        insert into "better_supabase"."permissions" ("key") values (v_key) returning "id" into v_new;
      end if;
      insert into "better_supabase"."role_permissions" ("role_id", "permission_id")
      select l."role_id", v_new from "better_supabase"."role_permissions" l where l."permission_id" = v_old
      on conflict do nothing;
      insert into "better_supabase"."permission_overrides" ("organization_id", "role_id", "permission_id", "granted")
      select o."organization_id", o."role_id", v_new, o."granted"
      from "better_supabase"."permission_overrides" o
      where o."permission_id" = v_old
      on conflict do nothing;
    end loop;

    if r.retire then
      delete from "better_supabase"."permissions" where "id" = v_old;
    end if;
  end loop;

  if v_changed and to_regprocedure('better_supabase.bump_authz_versions(uuid[])') is not null then
    execute 'select better_supabase.bump_authz_versions(array(select id from auth.users))';
  end if;
end;
$$;

insert into better_supabase.blocks (name, version, mode)
values ('permissions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: organizations
-- @bsb-block-data organizations
-- @bsb-hash sha256:0d61554664bed8777168e5f25e0b8597db7416b5b7439e346866162aed0f4f0b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('organizations', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: profiles
-- @bsb-block-data profiles
-- @bsb-hash sha256:ab80b3837365dff9910f5918c9250069c5fc621b6f8fe7ab925508801c48eb9f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Warns about another trigger that also creates profiles (handle_new_user).
select better_supabase.replace_equivalent_triggers('auth.users', 'bsb_profile_sync', '(handle_new_user|create_profile|new_user_profile)', false);

insert into better_supabase.blocks (name, version, mode)
values ('profiles', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: outbox
-- @bsb-block-data outbox
-- @bsb-hash sha256:83eb93332508b2972b76630f6941b38e43332a0a7a7f04fd1fa02c019c142969
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Event types renamed by the 0.47 naming convention (ADR 0130).
update "better_supabase"."outbox_events" t set "type" = m.next_type
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
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
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
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."type" = m.old_type;

update "better_supabase"."outbox_dead_letters" t set "type" = m.next_type
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
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
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
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."type" = m.old_type;

with m(old_type, next_types) as (values
  ('access.*', array['access_request.*']::text[]),
  ('access.ended', array['access_request.ended']::text[]),
  ('access.request_approved', array['access_request.approved']::text[]),
  ('access.requested', array['access_request.requested']::text[]),
  ('agent.saved', array['agent.created', 'agent.updated']::text[]),
  ('ai_provider_key.saved', array['ai_provider_key.created', 'ai_provider_key.updated']::text[]),
  ('ai_tool_policy.set', array['ai_tool_policy.updated']::text[]),
  ('announcement.saved', array['announcement.created', 'announcement.updated']::text[]),
  ('approval_policy.removed', array['approval_policy.deleted']::text[]),
  ('approval_policy.saved', array['approval_policy.created', 'approval_policy.updated']::text[]),
  ('compliance_policy.acknowledged', array['acknowledgement.created']::text[]),
  ('connector.saved', array['connector.created', 'connector.updated']::text[]),
  ('control.saved', array['control.created', 'control.updated']::text[]),
  ('course.saved', array['course.created', 'course.updated']::text[]),
  ('credential.set', array['credential.updated']::text[]),
  ('custom_field.*', array['field_definition.*']::text[]),
  ('custom_field.deleted', array['field_definition.deleted']::text[]),
  ('custom_field.saved', array['field_definition.created', 'field_definition.updated']::text[]),
  ('drive.*', array['drive_node.*']::text[]),
  ('drive.node_created', array['drive_node.created']::text[]),
  ('drive.node_document_saved', array['drive_node.document_saved']::text[]),
  ('drive.node_download_blocked_changed', array['drive_node.download_blocked_changed']::text[]),
  ('drive.node_hold_placed', array['drive_node.hold_placed']::text[]),
  ('drive.node_hold_released', array['drive_node.hold_released']::text[]),
  ('drive.node_locked', array['drive_node.locked']::text[]),
  ('drive.node_moved', array['drive_node.moved']::text[]),
  ('drive.node_obsoleted', array['drive_node.obsoleted']::text[]),
  ('drive.node_ownership_transferred', array['drive_node.ownership_transferred']::text[]),
  ('drive.node_purged', array['drive_node.purged']::text[]),
  ('drive.node_released', array['drive_node.released']::text[]),
  ('drive.node_renamed', array['drive_node.renamed']::text[]),
  ('drive.node_review_requested', array['drive_node.review_requested']::text[]),
  ('drive.node_reviewed', array['drive_node.reviewed']::text[]),
  ('drive.node_shared', array['drive_node.shared']::text[]),
  ('drive.node_submitted', array['drive_node.submitted']::text[]),
  ('drive.node_unlocked', array['drive_node.unlocked']::text[]),
  ('drive.node_unshared', array['drive_node.unshared']::text[]),
  ('engagement.*', array['activity.*']::text[]),
  ('engagement.amended', array['activity.amended']::text[]),
  ('engagement.completed', array['activity.completed']::text[]),
  ('engagement.deleted', array['activity.deleted']::text[]),
  ('engagement.error_marked', array['activity.error_marked']::text[]),
  ('engagement.logged', array['activity.logged']::text[]),
  ('engagement.recorded', array['activity.recorded']::text[]),
  ('engagement.summarized', array['activity.summarized']::text[]),
  ('engagement.transcribed', array['activity.transcribed']::text[]),
  ('engagement.updated', array['activity.updated']::text[]),
  ('enrollment_program.saved', array['enrollment_program.created', 'enrollment_program.updated']::text[]),
  ('flag.override_set', array['flag.override_changed']::text[]),
  ('flag.saved', array['flag.created', 'flag.updated']::text[]),
  ('forecast.*', array['forecast_snapshot.*']::text[]),
  ('forecast.snapshotted', array['forecast_snapshot.created']::text[]),
  ('hostname.primary_set', array['hostname.primary_changed']::text[]),
  ('hostname.removed', array['hostname.deleted']::text[]),
  ('incoming_webhook.enabled_set', array['incoming_webhook.enabled_changed']::text[]),
  ('job.*', array['job_opening.*']::text[]),
  ('job.closed', array['job_opening.closed']::text[]),
  ('job.opened', array['job_opening.opened']::text[]),
  ('leave.*', array['leave_request.*', 'leave_balance.*']::text[]),
  ('leave.adjusted', array['leave_balance.adjusted']::text[]),
  ('leave.approved', array['leave_request.approved']::text[]),
  ('leave.cancelled', array['leave_request.cancelled']::text[]),
  ('leave.rejected', array['leave_request.rejected']::text[]),
  ('leave.requested', array['leave_request.requested']::text[]),
  ('leave.split', array['leave_request.split']::text[]),
  ('leave.updated', array['leave_request.updated']::text[]),
  ('marketplace_installation.removed', array['marketplace_installation.deleted']::text[]),
  ('marketplace_installation.upserted', array['marketplace_installation.created', 'marketplace_installation.updated']::text[]),
  ('marketplace_invoice.state_changed', array['marketplace_invoice.status_changed']::text[]),
  ('obligation.*', array['contract_obligation.*']::text[]),
  ('obligation.saved', array['contract_obligation.created', 'contract_obligation.updated']::text[]),
  ('obligation.status_changed', array['contract_obligation.status_changed']::text[]),
  ('organization.*', array['sso_domain.*']::text[]),
  ('organization.domain_added', array['sso_domain.created']::text[]),
  ('organization.domain_removed', array['sso_domain.deleted']::text[]),
  ('organization.domain_updated', array['sso_domain.updated']::text[]),
  ('organization.domain_verified', array['sso_domain.verified']::text[]),
  ('party.*', array['company.enriched', 'person.enriched']::text[]),
  ('party.enriched', array['company.enriched', 'person.enriched']::text[]),
  ('pipeline_stage.saved', array['pipeline_stage.created', 'pipeline_stage.updated']::text[]),
  ('policy.*', array['compliance_policy.*']::text[]),
  ('policy.acknowledged', array['acknowledgement.created']::text[]),
  ('policy.published', array['compliance_policy.published']::text[]),
  ('post_board.saved', array['post_board.created', 'post_board.updated']::text[]),
  ('postmortem.*', array['incident_postmortem.*']::text[]),
  ('postmortem.published', array['incident_postmortem.published']::text[]),
  ('rule.*', array['automation.*']::text[]),
  ('rule.disabled', array['automation.disabled']::text[]),
  ('rule.enabled', array['automation.enabled']::text[]),
  ('rule.matched', array['automation.matched']::text[]),
  ('rule.removed', array['automation.deleted']::text[]),
  ('rule.saved', array['automation.created', 'automation.updated']::text[]),
  ('saved_view.saved', array['saved_view.created', 'saved_view.updated']::text[]),
  ('scim_group.saved', array['scim_group.created', 'scim_group.updated']::text[]),
  ('scim_user.saved', array['scim_user.created', 'scim_user.updated']::text[]),
  ('score_model.saved', array['score_model.created', 'score_model.updated']::text[]),
  ('segment.removed', array['segment.deleted']::text[]),
  ('segment.saved', array['segment.created', 'segment.updated']::text[]),
  ('sequence.saved', array['sequence.created', 'sequence.updated']::text[]),
  ('sequence_enrollment.*', array['enrollment.*']::text[]),
  ('sequence_enrollment.completed', array['enrollment.completed']::text[]),
  ('sequence_enrollment.created', array['enrollment.created']::text[]),
  ('sequence_enrollment.exited', array['enrollment.cancelled']::text[]),
  ('sequence_enrollment.paused', array['enrollment.paused']::text[]),
  ('sequence_enrollment.resumed', array['enrollment.resumed']::text[]),
  ('sequence_enrollment.step_completed', array['enrollment.step_completed']::text[]),
  ('signature.*', array['signature_request.*']::text[]),
  ('signature.cancelled', array['signature_request.cancelled']::text[]),
  ('signature.completed', array['signature_request.completed']::text[]),
  ('signature.declined', array['signature_request.declined']::text[]),
  ('signature.requested', array['signature_request.requested']::text[]),
  ('signature.signed', array['signature_request.signed']::text[]),
  ('support.*', array['support_session.*']::text[]),
  ('support.denied', array['support_session.denied']::text[]),
  ('support.ended', array['support_session.ended']::text[]),
  ('support.started', array['support_session.started']::text[]),
  ('time.*', array['time_entry.*']::text[]),
  ('time.invoiced', array['time_entry.invoiced']::text[]),
  ('variant.*', array['product_variant.*']::text[]),
  ('variant.created', array['product_variant.created']::text[]),
  ('variant.deleted', array['product_variant.deleted']::text[]),
  ('variant.updated', array['product_variant.updated']::text[]),
  ('waitlist.*', array['waitlist_entry.*']::text[]),
  ('waitlist.approved', array['waitlist_entry.approved']::text[]),
  ('waitlist.rejected', array['waitlist_entry.rejected']::text[]),
  ('webhook.*', array['webhook_endpoint.*']::text[]),
  ('webhook.delivered', array['webhook_endpoint.delivered']::text[]),
  ('webhook.disabled', array['webhook_endpoint.disabled']::text[]),
  ('webhook.failed', array['webhook_endpoint.failed']::text[]),
  ('webhook.secret_rotated', array['webhook_endpoint.secret_rotated']::text[]),
  ('workflow.*', array['workflow_definition.*']::text[]),
  ('workflow.published', array['workflow_definition.published']::text[])
)
update "better_supabase"."outbox_consumers" t set "types" = array(
  select distinct x from unnest(t."types" || array(
    select n from unnest(t."types") o join m on m.old_type = o
    cross join unnest(m.next_types) n
  )) x order by x
)
where t."types" && array(select old_type from m);

insert into better_supabase.blocks (name, version, mode)
values ('outbox', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: notifications
-- @bsb-block-data notifications
-- @bsb-hash sha256:bfc5247523bcdb57cdb4645ed107de16d8675d27c58c33c43c97c28326b8dde3
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('notifications', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: webhooks-out
-- @bsb-block-data webhooks-out
-- @bsb-hash sha256:e22059a63e739ae8299b6d48935aa83fdb23207bfb06cafad37e87d2239456d5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Event types renamed by the 0.47 naming convention (ADR 0130).
with m(old_type, next_types) as (values
  ('access.*', array['access_request.*']::text[]),
  ('access.ended', array['access_request.ended']::text[]),
  ('access.request_approved', array['access_request.approved']::text[]),
  ('access.requested', array['access_request.requested']::text[]),
  ('agent.saved', array['agent.created', 'agent.updated']::text[]),
  ('ai_provider_key.saved', array['ai_provider_key.created', 'ai_provider_key.updated']::text[]),
  ('ai_tool_policy.set', array['ai_tool_policy.updated']::text[]),
  ('announcement.saved', array['announcement.created', 'announcement.updated']::text[]),
  ('approval_policy.removed', array['approval_policy.deleted']::text[]),
  ('approval_policy.saved', array['approval_policy.created', 'approval_policy.updated']::text[]),
  ('compliance_policy.acknowledged', array['acknowledgement.created']::text[]),
  ('connector.saved', array['connector.created', 'connector.updated']::text[]),
  ('control.saved', array['control.created', 'control.updated']::text[]),
  ('course.saved', array['course.created', 'course.updated']::text[]),
  ('credential.set', array['credential.updated']::text[]),
  ('custom_field.*', array['field_definition.*']::text[]),
  ('custom_field.deleted', array['field_definition.deleted']::text[]),
  ('custom_field.saved', array['field_definition.created', 'field_definition.updated']::text[]),
  ('drive.*', array['drive_node.*']::text[]),
  ('drive.node_created', array['drive_node.created']::text[]),
  ('drive.node_document_saved', array['drive_node.document_saved']::text[]),
  ('drive.node_download_blocked_changed', array['drive_node.download_blocked_changed']::text[]),
  ('drive.node_hold_placed', array['drive_node.hold_placed']::text[]),
  ('drive.node_hold_released', array['drive_node.hold_released']::text[]),
  ('drive.node_locked', array['drive_node.locked']::text[]),
  ('drive.node_moved', array['drive_node.moved']::text[]),
  ('drive.node_obsoleted', array['drive_node.obsoleted']::text[]),
  ('drive.node_ownership_transferred', array['drive_node.ownership_transferred']::text[]),
  ('drive.node_purged', array['drive_node.purged']::text[]),
  ('drive.node_released', array['drive_node.released']::text[]),
  ('drive.node_renamed', array['drive_node.renamed']::text[]),
  ('drive.node_review_requested', array['drive_node.review_requested']::text[]),
  ('drive.node_reviewed', array['drive_node.reviewed']::text[]),
  ('drive.node_shared', array['drive_node.shared']::text[]),
  ('drive.node_submitted', array['drive_node.submitted']::text[]),
  ('drive.node_unlocked', array['drive_node.unlocked']::text[]),
  ('drive.node_unshared', array['drive_node.unshared']::text[]),
  ('engagement.*', array['activity.*']::text[]),
  ('engagement.amended', array['activity.amended']::text[]),
  ('engagement.completed', array['activity.completed']::text[]),
  ('engagement.deleted', array['activity.deleted']::text[]),
  ('engagement.error_marked', array['activity.error_marked']::text[]),
  ('engagement.logged', array['activity.logged']::text[]),
  ('engagement.recorded', array['activity.recorded']::text[]),
  ('engagement.summarized', array['activity.summarized']::text[]),
  ('engagement.transcribed', array['activity.transcribed']::text[]),
  ('engagement.updated', array['activity.updated']::text[]),
  ('enrollment_program.saved', array['enrollment_program.created', 'enrollment_program.updated']::text[]),
  ('flag.override_set', array['flag.override_changed']::text[]),
  ('flag.saved', array['flag.created', 'flag.updated']::text[]),
  ('forecast.*', array['forecast_snapshot.*']::text[]),
  ('forecast.snapshotted', array['forecast_snapshot.created']::text[]),
  ('hostname.primary_set', array['hostname.primary_changed']::text[]),
  ('hostname.removed', array['hostname.deleted']::text[]),
  ('incoming_webhook.enabled_set', array['incoming_webhook.enabled_changed']::text[]),
  ('job.*', array['job_opening.*']::text[]),
  ('job.closed', array['job_opening.closed']::text[]),
  ('job.opened', array['job_opening.opened']::text[]),
  ('leave.*', array['leave_request.*', 'leave_balance.*']::text[]),
  ('leave.adjusted', array['leave_balance.adjusted']::text[]),
  ('leave.approved', array['leave_request.approved']::text[]),
  ('leave.cancelled', array['leave_request.cancelled']::text[]),
  ('leave.rejected', array['leave_request.rejected']::text[]),
  ('leave.requested', array['leave_request.requested']::text[]),
  ('leave.split', array['leave_request.split']::text[]),
  ('leave.updated', array['leave_request.updated']::text[]),
  ('marketplace_installation.removed', array['marketplace_installation.deleted']::text[]),
  ('marketplace_installation.upserted', array['marketplace_installation.created', 'marketplace_installation.updated']::text[]),
  ('marketplace_invoice.state_changed', array['marketplace_invoice.status_changed']::text[]),
  ('obligation.*', array['contract_obligation.*']::text[]),
  ('obligation.saved', array['contract_obligation.created', 'contract_obligation.updated']::text[]),
  ('obligation.status_changed', array['contract_obligation.status_changed']::text[]),
  ('organization.*', array['sso_domain.*']::text[]),
  ('organization.domain_added', array['sso_domain.created']::text[]),
  ('organization.domain_removed', array['sso_domain.deleted']::text[]),
  ('organization.domain_updated', array['sso_domain.updated']::text[]),
  ('organization.domain_verified', array['sso_domain.verified']::text[]),
  ('party.*', array['company.enriched', 'person.enriched']::text[]),
  ('party.enriched', array['company.enriched', 'person.enriched']::text[]),
  ('pipeline_stage.saved', array['pipeline_stage.created', 'pipeline_stage.updated']::text[]),
  ('policy.*', array['compliance_policy.*']::text[]),
  ('policy.acknowledged', array['acknowledgement.created']::text[]),
  ('policy.published', array['compliance_policy.published']::text[]),
  ('post_board.saved', array['post_board.created', 'post_board.updated']::text[]),
  ('postmortem.*', array['incident_postmortem.*']::text[]),
  ('postmortem.published', array['incident_postmortem.published']::text[]),
  ('rule.*', array['automation.*']::text[]),
  ('rule.disabled', array['automation.disabled']::text[]),
  ('rule.enabled', array['automation.enabled']::text[]),
  ('rule.matched', array['automation.matched']::text[]),
  ('rule.removed', array['automation.deleted']::text[]),
  ('rule.saved', array['automation.created', 'automation.updated']::text[]),
  ('saved_view.saved', array['saved_view.created', 'saved_view.updated']::text[]),
  ('scim_group.saved', array['scim_group.created', 'scim_group.updated']::text[]),
  ('scim_user.saved', array['scim_user.created', 'scim_user.updated']::text[]),
  ('score_model.saved', array['score_model.created', 'score_model.updated']::text[]),
  ('segment.removed', array['segment.deleted']::text[]),
  ('segment.saved', array['segment.created', 'segment.updated']::text[]),
  ('sequence.saved', array['sequence.created', 'sequence.updated']::text[]),
  ('sequence_enrollment.*', array['enrollment.*']::text[]),
  ('sequence_enrollment.completed', array['enrollment.completed']::text[]),
  ('sequence_enrollment.created', array['enrollment.created']::text[]),
  ('sequence_enrollment.exited', array['enrollment.cancelled']::text[]),
  ('sequence_enrollment.paused', array['enrollment.paused']::text[]),
  ('sequence_enrollment.resumed', array['enrollment.resumed']::text[]),
  ('sequence_enrollment.step_completed', array['enrollment.step_completed']::text[]),
  ('signature.*', array['signature_request.*']::text[]),
  ('signature.cancelled', array['signature_request.cancelled']::text[]),
  ('signature.completed', array['signature_request.completed']::text[]),
  ('signature.declined', array['signature_request.declined']::text[]),
  ('signature.requested', array['signature_request.requested']::text[]),
  ('signature.signed', array['signature_request.signed']::text[]),
  ('support.*', array['support_session.*']::text[]),
  ('support.denied', array['support_session.denied']::text[]),
  ('support.ended', array['support_session.ended']::text[]),
  ('support.started', array['support_session.started']::text[]),
  ('time.*', array['time_entry.*']::text[]),
  ('time.invoiced', array['time_entry.invoiced']::text[]),
  ('variant.*', array['product_variant.*']::text[]),
  ('variant.created', array['product_variant.created']::text[]),
  ('variant.deleted', array['product_variant.deleted']::text[]),
  ('variant.updated', array['product_variant.updated']::text[]),
  ('waitlist.*', array['waitlist_entry.*']::text[]),
  ('waitlist.approved', array['waitlist_entry.approved']::text[]),
  ('waitlist.rejected', array['waitlist_entry.rejected']::text[]),
  ('webhook.*', array['webhook_endpoint.*']::text[]),
  ('webhook.delivered', array['webhook_endpoint.delivered']::text[]),
  ('webhook.disabled', array['webhook_endpoint.disabled']::text[]),
  ('webhook.failed', array['webhook_endpoint.failed']::text[]),
  ('webhook.secret_rotated', array['webhook_endpoint.secret_rotated']::text[]),
  ('workflow.*', array['workflow_definition.*']::text[]),
  ('workflow.published', array['workflow_definition.published']::text[])
)
update "better_supabase"."webhook_endpoints" t set "event_types" = array(
  select distinct x from unnest(t."event_types" || array(
    select n from unnest(t."event_types") o join m on m.old_type = o
    cross join unnest(m.next_types) n
  )) x order by x
)
where t."event_types" && array(select old_type from m);

insert into better_supabase.blocks (name, version, mode)
values ('webhooks-out', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: sessions
-- @bsb-block-data sessions
-- @bsb-hash sha256:6afd74c5a23b192fe1cd9ad6d1b70ee22dcbde1306ce978089853db5fa05bc17
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sessions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: api-keys
-- @bsb-block-data api-keys
-- @bsb-hash sha256:d000d6b4af22ccfa33ed783ca7a0f5854cda14a231737270afde85b5036d7b57
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('api-keys', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: settings
-- @bsb-block-data settings
-- @bsb-hash sha256:7170a272de43c0c913d1b01e73565030d8974fb94e0fe36b6f491e1e6fc009e5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('settings', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: usage
-- @bsb-block-data usage
-- @bsb-hash sha256:7ef3669a0e5f7212dedcb8d76ca839b1218039254cfe9c9b909e71d3f6f31ada
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('usage', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: flags
-- @bsb-block-data flags
-- @bsb-hash sha256:4036cb86aa3b85d73b2ac180acf313c89af7cdb5b89f3c1de52a83f004a060dd
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('flags', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: drive
-- @bsb-block-data drive
-- @bsb-hash sha256:456861a8de132fa0ec1a416d10fa30a61c07cbd9e9db22f20aecfdab2ba94bab
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('drive', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: guests
-- @bsb-block-data guests
-- @bsb-hash sha256:4a19d1ee72e2093a935c6efbfefa8034950fd9bfb109063d45605c54bd34d9a6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('guests', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: comments
-- @bsb-block-data comments
-- @bsb-hash sha256:b88720e1f8db856027df7f4a32cd82bc30bc62603e455805ccbce770f292744d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('comments', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: attachments
-- @bsb-block-data attachments
-- @bsb-hash sha256:4a5d8f0e51c3e915f48ef994cb5516725a1ca9707f2b45f3680af9c6dc3767e5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 52428800, null)
on conflict (id) do update set public = excluded.public;

insert into better_supabase.blocks (name, version, mode)
values ('attachments', 7, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: data-lifecycle
-- @bsb-block-data data-lifecycle
-- @bsb-hash sha256:91b1ecf37bdadc8a3837d47fa1a7dddb9d1dac6e489fc3acc79652fa7b1103b6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public)
values ('data-exports', 'data-exports', false)
on conflict (id) do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('data-lifecycle', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: sso
-- @bsb-block-data sso
-- @bsb-hash sha256:4e15cb7f5681d67d521fd3650ecde834e8c36e733c21f7648242709248220a95
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sso', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: enrollments
-- @bsb-block-data enrollments
-- @bsb-hash sha256:ba27786140fd499c4d1e2ab814ef20ead1970f014ec0279b82377d83afb2017a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('enrollments', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: onboarding
-- @bsb-block-data onboarding
-- @bsb-hash sha256:a7fd47a7b0d152603b5cd802ba44eec18eae8862cdfb4e38e2e7a28f6d5038c2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('onboarding', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: waitlist
-- @bsb-block-data waitlist
-- @bsb-hash sha256:d2114d835d02603771b06e4c11a5f251e18b9573fe93b85c85fa3c3fa26c3374
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('waitlist', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: announcements
-- @bsb-block-data announcements
-- @bsb-hash sha256:60ebe88a3adfda6790a201adc72f29be4d50593ece2281d013078f8e48a2dc8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('announcements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: streams
-- @bsb-block-data streams
-- @bsb-hash sha256:1f571b7111ca0d4a41a6b8d65e6b5857c553e90a9206d5faaddb919ae530767d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('streams', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: credentials
-- @bsb-block-data credentials
-- @bsb-hash sha256:3d1dc5f51081386b5208cc7fc619b0d93bf725b4d1b8f33978d7c8eaf0c602c6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('credentials', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: workflows
-- @bsb-block-data workflows
-- @bsb-hash sha256:4237851ec792fdbc3434d71841e2707e563966c6d7b09e7bada102fc206b95e4
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('workflows', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: workflow-sdk
-- @bsb-block-data workflow-sdk
-- @bsb-hash sha256:074bf56c8ea1c04a26b7e5ac10159ae775306c562aa9cd6fada431f31f21d8a4
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('workflow-sdk', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: workflow-editor
-- @bsb-block-data workflow-editor
-- @bsb-hash sha256:09d9c614c5c08b616fc80df99dd8fdf2508fa5ee576a21a3811fb7217f44e6b2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('workflow-editor', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: chat-sdk-state
-- @bsb-block-data chat-sdk-state
-- @bsb-hash sha256:e690135d628b82479ec3c852388f8891214f6edb498ad86a1308c002ecdde5ea
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('chat-sdk-state', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: inbox
-- @bsb-block-data inbox
-- @bsb-hash sha256:79245cdaa38a43aba6e4527e2193e8cd4381ad2088a345648c1926683d1d866c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "better_supabase"."automation_defaults" ("key", "block", "subject_type", "trigger", "name", "description", "actions", "enabled")
values ('inbox.conversation_to_task', 'inbox', 'inbox_conversation', 'inbox_conversation.opened', 'Open a task for each new conversation', 'Creates a task from the conversation''s subject and preview, assigned to the conversation''s assignee and linked created_from the conversation.', '[{"kind":"tasks.from_conversation","config":{"targetType":"work_item"}}]'::jsonb, true)
on conflict ("key") do update set "subject_type" = excluded."subject_type", "trigger" = excluded."trigger", "name" = excluded."name", "description" = excluded."description", "actions" = excluded."actions", "enabled" = excluded."enabled", "block" = excluded."block", "updated_at" = now();

insert into better_supabase.blocks (name, version, mode)
values ('inbox', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: ai-chat
-- @bsb-block-data ai-chat
-- @bsb-hash sha256:73b87d6a0a1ad5526043b115f20eac6eab1378367f4b0351a1d92c4dc5d986aa
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-chat', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: ai-files
-- @bsb-block-data ai-files
-- @bsb-hash sha256:684e7b9e960299f392102915f4634379689c20b48c17e84030e8c014c6f5d11b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ai-files', 'ai-files', false, 52428800, null)
on conflict (id) do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('ai-files', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: knowledge
-- @bsb-block-data knowledge
-- @bsb-hash sha256:58dae03b410f817eaaaf517fe03bf25200266c96a4479809706fc0a07facf474
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('knowledge', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: memory
-- @bsb-block-data memory
-- @bsb-hash sha256:c9ee4b319d14d465c6f95834df79c6fe7d16c7730b2450ff8ad4fba0175be588
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('memory', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: agents
-- @bsb-block-data agents
-- @bsb-hash sha256:fa9cc60129a717eb5ea5b829cf6bed0d4a193231f3561c5e8513dff5c7b710ff
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('agents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: connectors
-- @bsb-block-data connectors
-- @bsb-hash sha256:29335edcb89ba93004fa70b32f46f952067127195fa6ca8c364721346dd947e6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('connectors', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: ai-schedules
-- @bsb-block-data ai-schedules
-- @bsb-hash sha256:43de88ba0dbb65c1156d816eb749533bf1807cd81b507d4dcf3059b78c44d38f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-schedules', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: push
-- @bsb-block-data push
-- @bsb-hash sha256:e141b953e8ced89dc002e0611cccf4b33b61b5e39d0578eae82e89493358840c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('push', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: ai-cache
-- @bsb-block-data ai-cache
-- @bsb-hash sha256:24b9c0173f55096a24f3173dc48fc3c2dcbdb9d5e6b1816f0223ef9834dcab18
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-cache', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: ai-keys
-- @bsb-block-data ai-keys
-- @bsb-hash sha256:59f49d5cd582b88f958553f7215a99189f65f822edc9f26c08913b28d7fe4b72
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-keys', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: numbering
-- @bsb-block-data numbering
-- @bsb-hash sha256:a66767a6e66d7ecf17d8a2fc5db1a3382c51337c245be2005a35a304ae3d1155
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('numbering', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: teams
-- @bsb-block-data teams
-- @bsb-hash sha256:73dfb8a9526ca418c3217dfe9e93bcf5b07006c37b0a318922295a314a8ee6c9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('teams', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: tags
-- @bsb-block-data tags
-- @bsb-hash sha256:baa1d5b6721528e763808c231522383a33db513a6254d0a316c15c1087308cb6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tags', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: state-machine
-- @bsb-block-data state-machine
-- @bsb-hash sha256:eed0cde016d3acd0ea24fb6d8c5faf9cfd3417857dd07b02e0b4266dfa97fe1c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('state-machine', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: custom-fields
-- @bsb-block-data custom-fields
-- @bsb-hash sha256:2f372e03cc31a3775142510e905c3eac5585015d0adfc00b13e88d16eeb1e378
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: share-links
-- @bsb-block-data share-links
-- @bsb-hash sha256:7637f6eb6b2307a7cf52549ce1a65dbedbf85875d12cb740b65ff82e13399bd6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('share-links', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: reminders
-- @bsb-block-data reminders
-- @bsb-hash sha256:d2fe5d73d65cd57fa991248140b2f47de077d33f44e6e190b9e0d3012d0ab3b8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('reminders', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: imports
-- @bsb-block-data imports
-- @bsb-hash sha256:03c82178dd5c9af38535aa92f90002ada8c21fab4dadb8d91c33605f8bdcec29
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('imports', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: subjects
-- @bsb-block-data subjects
-- @bsb-hash sha256:eb0303aed8e9092aca1e8d0972e3a1d7ed2016a525be423d7feb911c659f913c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('subjects', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: rank
-- @bsb-block-data rank
-- @bsb-hash sha256:f798697a0fce2c8a2157fde8c520ec5a38596bbc3870a3e082a069358fbb3c7a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('rank', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: saved-views
-- @bsb-block-data saved-views
-- @bsb-hash sha256:c7b5642e8303e22583d102851c071a83d2a86b6f5ab0aca5d15da41af490dba2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('saved-views', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: relations
-- @bsb-block-data relations
-- @bsb-hash sha256:7f45922dc27a85579c3fd0b09d0b2504d8a3fc579388a16f2bd423a834360920
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('relations', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: bulk
-- @bsb-block-data bulk
-- @bsb-hash sha256:4573a67d75005a6c7627cf2425e408dc4794252b6f0c4f6071c63da3cb56894e
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('bulk', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: catalog
-- @bsb-block-data catalog
-- @bsb-hash sha256:f1b2b4ddf75f743b52b4e2090b59663b897cde55903fcfa589ff6dc45f0bb9b9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('catalog', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: search
-- @bsb-block-data search
-- @bsb-hash sha256:66567248bb467258295a86977c4ccf9a52d7404124948f9b1d0d531e3b00cb74
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pg_trgm" with schema "extensions";
create extension if not exists "unaccent" with schema "extensions";

-- Indexes the rows that existed before the triggers.
select "better_supabase"."search_reindex"();

insert into better_supabase.blocks (name, version, mode)
values ('search', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: metrics
-- @bsb-block-data metrics
-- @bsb-hash sha256:fcee29fea442efd6e7f2a62cbe985ebe2042e444f6d412430eb8b979ba0fb642
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('metrics', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: calendar
-- @bsb-block-data calendar
-- @bsb-hash sha256:d394b8cd042344b4f2cc937a4b1a75f47403ab3daa823c307e6f4711cc462311
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('calendar', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: bookings
-- @bsb-block-data bookings
-- @bsb-hash sha256:01e1d19922ddc759d5754a0f61158ad5181bc611238d2a91dad9476309f95673
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('bookings', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: versions
-- @bsb-block-data versions
-- @bsb-hash sha256:3867036bd3026f5dbb651b697e61ba4c769803093a644280a8a15313b9e97c36
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('versions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: trash
-- @bsb-block-data trash
-- @bsb-hash sha256:24d0f2ecaf819874fb898f6b205c5f6c365b78955412bee3ada0390cce9376c4
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('trash', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: reactions
-- @bsb-block-data reactions
-- @bsb-hash sha256:5deb9a6c5e8fa6ac34d3276a3a2aad0f2b697ad0b07b884da22c9ed016f895f8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('reactions', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: approvals
-- @bsb-block-data approvals
-- @bsb-hash sha256:42c6ed9866679559107e98b7c390497981bf36b42dc763f3dc29712a073bb21e
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('approvals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: access-requests
-- @bsb-block-data access-requests
-- @bsb-hash sha256:5ecfb15306bd8d51b0820b8afc96355b2183538887699d447a1077c7e0e498cf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('access-requests', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: documents
-- @bsb-block-data documents
-- @bsb-hash sha256:a3907dcc75373f668c797d067d33e3661c05843c1b0474a550c3b0e322cbe981
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('documents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: ledger
-- @bsb-block-data ledger
-- @bsb-hash sha256:06938b221990c160f1a1ccd8d1df9f3ab7420e37c18081a48be4a911fac889a0
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ledger', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: inventory
-- @bsb-block-data inventory
-- @bsb-hash sha256:ea44e3b8b1525a301ac30a33b17c5ce2127de622ef0df73b59a9a10aa7fb8a72
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inventory', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: drive-files
-- @bsb-block-data drive-files
-- @bsb-hash sha256:a9de9d58b473f459508f98079d0d866885f96d734c53177ddc265cc3291cd7ee
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('drive-files', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: orders
-- @bsb-block-data orders
-- @bsb-hash sha256:9e7cf68a92d30df8f4303e95812a9d1f5c8e94508111060e75de394239f87417
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('orders', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: promotions
-- @bsb-block-data promotions
-- @bsb-hash sha256:6613b495bfa7fde131886986f78b3cfc77e334ad1345649f8c2f1453ac6f9b29
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('promotions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: forms
-- @bsb-block-data forms
-- @bsb-hash sha256:ba046d701cddbc2f816944c4e89a65d5c3aa2d200a4356ce41ce71820acfd8f0
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('forms', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: signatures
-- @bsb-block-data signatures
-- @bsb-hash sha256:60d4f60f0497e6f4c25a101c6509c7c3f2624d76a1b38ef0dd34918d9d221802
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('signatures', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: time-tracking
-- @bsb-block-data time-tracking
-- @bsb-hash sha256:cbca636a87fb7e287885e64e34603f4dbdacbf5b55e5e4d6bc02aac85dea8fb2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('time-tracking', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: service-accounts
-- @bsb-block-data service-accounts
-- @bsb-hash sha256:2d9091abeb693d8556dc11a1b6b34bbc1e216cb6c5198c9d7c58f6dad7b37ec1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('service-accounts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: templates
-- @bsb-block-data templates
-- @bsb-hash sha256:b8f109c9be802b16766dc2421c68f34cacf2322c02b9c507938fd08f01f94689
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('templates', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: cases
-- @bsb-block-data cases
-- @bsb-hash sha256:7afd439d1b21eec44b1f4de82df17f086b4ae6d4cad1aa229d975cec46001b05
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('cases', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: deals
-- @bsb-block-data deals
-- @bsb-hash sha256:bc42cb9cecbcea4c32998adc94b1f530ec22c47381cf471722c5a14acedbe624
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('deals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: hiring
-- @bsb-block-data hiring
-- @bsb-hash sha256:ecb394318a7f0a663d198da337981d9f1aaca2eb00a3f886abc543a6eb4ad201
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "better_supabase"."automation_defaults" ("key", "block", "subject_type", "trigger", "name", "description", "actions", "enabled")
values ('hiring.application_to_employee', 'hiring', 'application', 'application.hired', 'Preboard each hired candidate', 'Creates an employee in preboarding from the hired application''s candidate and job, linked created_from the application.', '[{"kind":"employees.from_application","config":{"targetType":"employee"}}]'::jsonb, true)
on conflict ("key") do update set "subject_type" = excluded."subject_type", "trigger" = excluded."trigger", "name" = excluded."name", "description" = excluded."description", "actions" = excluded."actions", "enabled" = excluded."enabled", "block" = excluded."block", "updated_at" = now();

insert into better_supabase.blocks (name, version, mode)
values ('hiring', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: tasks
-- @bsb-block-data tasks
-- @bsb-hash sha256:1d33602116152b97634d65a65d0514b39e13976668420f91b0cda1a299acb4b8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Gives each existing project its value of the accounting project dimension.
select "better_supabase"."accounting_sync_dimension_value"(x."tenant_id", 'project', 'Project', x."id"::text, x."key" || ' ' || x."name", x."archived_at" is not null)
from "better_supabase"."work_projects" x
where exists (select 1 from "better_supabase"."accounting_settings" s where s."tenant_id" = x."tenant_id");

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: maintenance
-- @bsb-block-data maintenance
-- @bsb-hash sha256:a0ccc1da1ce32a36eafb5c579cb76ec4ab7c8d72a3f650115a74b857f4a49eaa
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

alter table better_supabase.blocks add column if not exists block text;
insert into better_supabase.blocks (name, block, version, mode)
values ('maintenance', 'tasks', 4, 'managed')
on conflict (name) do update
  set block = excluded.block, version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: pipelines
-- @bsb-block-data pipelines
-- @bsb-hash sha256:afbc833c2019b6deab1e41862c83cefb962a135052476adab19c5b7d64bafdad
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('pipelines', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: contacts
-- @bsb-block-data contacts
-- @bsb-hash sha256:ea2f398a8de372ad33e7c6e71272cb5815529be12dfab10287de9121a633dc5f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('contacts', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: activities
-- @bsb-block-data activities
-- @bsb-hash sha256:eda852d5dac82b0fbd0b4069d4af380a84391c6414ee1c4f26a3e5c0d7b17f7c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."notification_events"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."notification_events" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."notification_subscriptions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."notification_subscriptions" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."guest_grants"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."guest_grants" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."attachments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."attachments" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."data_exports"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."data_exports" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."enrollments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."enrollments" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."workflow_runs"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."workflow_runs" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."workflow_start_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."workflow_start_requests" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."knowledge_documents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."knowledge_documents" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."memories"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."memories" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."taggings"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."taggings" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."status_history"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."status_history" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."status_stages"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."status_stages" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_lifecycles"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_lifecycles" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."field_values"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."field_values" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."share_links"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."share_links" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_views"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_views" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_user_state"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_user_state" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."recurrence_rules"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."recurrence_rules" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reminders"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reminders" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."import_records"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."import_records" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_members"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_members" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."relations"') and attname = 'source_type' and not attisdropped) then update "better_supabase"."relations" set "source_type" = 'activity' where "source_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."relations"') and attname = 'target_type' and not attisdropped) then update "better_supabase"."relations" set "target_type" = 'activity' where "target_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."bulk_runs"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."bulk_runs" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."search_documents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."search_documents" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."calendar_events"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."calendar_events" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."calendar_attendees"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."calendar_attendees" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."versions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."versions" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."trash_items"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."trash_items" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reactions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reactions" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reaction_scores"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reaction_scores" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."approval_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."approval_requests" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."approval_policies"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."approval_policies" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."access_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."access_requests" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."documents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."documents" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."form_submissions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."form_submissions" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."signature_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."signature_requests" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."time_entries"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."time_entries" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."template_applications"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."template_applications" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipelines"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipelines" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipeline_stage_history"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipeline_stage_history" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."engagement_subjects"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."engagement_subjects" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."sla_policies"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."sla_policies" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."sla_clocks"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."sla_clocks" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."moderation_items"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."moderation_items" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."automations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."automations" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."automation_defaults"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."automation_defaults" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."automation_evaluations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."automation_evaluations" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."automation_fields"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."automation_fields" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."score_models"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."score_models" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."scores"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."scores" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."passes"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."passes" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."work_orders"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."work_orders" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."shipments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."shipments" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."conversations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."conversations" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."message_record_mentions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."message_record_mentions" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."channels"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."channels" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."timeline_entries"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."timeline_entries" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."mail_thread_subjects"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."mail_thread_subjects" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."segments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."segments" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."assignment_queues"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."assignment_queues" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."assignments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."assignments" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."field_changes"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."field_changes" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."lead_score_checks"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."lead_score_checks" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."qualification_requirements"') and attname = 'target_type' and not attisdropped) then update "better_supabase"."qualification_requirements" set "target_type" = 'activity' where "target_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."acknowledgement_assignments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."acknowledgement_assignments" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."acknowledgements"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."acknowledgements" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."acknowledgement_notices"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."acknowledgement_notices" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."consents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."consents" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."observations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."observations" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."medication_orders"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."medication_orders" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."care_plans"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."care_plans" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."bank_matches"') and attname = 'target_type' and not attisdropped) then update "better_supabase"."bank_matches" set "target_type" = 'activity' where "target_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."funding_awards"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."funding_awards" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."funding_deliveries"') and attname = 'source_type' and not attisdropped) then update "better_supabase"."funding_deliveries" set "source_type" = 'activity' where "source_type" = 'engagement'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('activities', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: quotes
-- @bsb-block-data quotes
-- @bsb-hash sha256:00b497b8917469395221371c4ecc8b46ed41520e1b677c52de1dcfa09fecdab4
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "better_supabase"."automation_defaults" ("key", "block", "subject_type", "trigger", "name", "description", "actions", "enabled")
values ('quotes.quote_to_order', 'quotes', 'quote', 'quote.accepted', 'Order each accepted quote', 'Creates an order for the accepted quote, linked created_from the quote, so an accepted quote orders once.', '[{"kind":"orders.from_quote","config":{"targetType":"order"}}]'::jsonb, false)
on conflict ("key") do update set "subject_type" = excluded."subject_type", "trigger" = excluded."trigger", "name" = excluded."name", "description" = excluded."description", "actions" = excluded."actions", "enabled" = excluded."enabled", "block" = excluded."block", "updated_at" = now();

insert into better_supabase.blocks (name, version, mode)
values ('quotes', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: invoices
-- @bsb-block-data invoices
-- @bsb-hash sha256:c00c51a11ad9c8aaa07dd314eed28f6c5079977dd7aed37e8fb1a704b4023060
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('invoices', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: sla
-- @bsb-block-data sla
-- @bsb-hash sha256:3a470193710382c34f047abbf9d2b499106a119c4e117a44c502d2ac46999a8a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sla', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: goals
-- @bsb-block-data goals
-- @bsb-hash sha256:6ccbb19a784390c80a73f1c3058be7d0e9d5e8f5641194f8c64fcbae29905639
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('goals', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: employees
-- @bsb-block-data employees
-- @bsb-hash sha256:ef71d36ecb32da43d32d40924d438f2ce86d6101484d71d537c5801e7d00355c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('employees', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: signing-keys
-- @bsb-block-data signing-keys
-- @bsb-hash sha256:edd36d64344238d41ca12d081d7d72ae73b18d9c79c7478b69dccbc76885ff2d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('signing-keys', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: moderation
-- @bsb-block-data moderation
-- @bsb-hash sha256:b01db3a657b26c96f56f50464078184599dffda20d933155ff1262b74ce1da6d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('moderation', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: automations
-- @bsb-block-data automations
-- @bsb-hash sha256:ac3e82d5d2d887b2694839df9617c2dbfcff632ad914aabbdc33aa37fdcc15b7
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Event types renamed by the 0.47 naming convention (ADR 0130).
update "better_supabase"."automations" t set "trigger" = m.next_type
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
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
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
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."trigger" = m.old_type;

update "better_supabase"."automation_defaults" t set "trigger" = m.next_type
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
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
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
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."trigger" = m.old_type;

insert into better_supabase.blocks (name, version, mode)
values ('automations', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: assets
-- @bsb-block-data assets
-- @bsb-hash sha256:a1bd4e939134879335c7da47b14fe6a1e8cd091e99c52bf6b106fb40741a1f99
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "postgis" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('assets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: scores
-- @bsb-block-data scores
-- @bsb-hash sha256:6f7c9cc86a08b5480b4f7941a14408ff700c102e1241a9529bcf6e776cacf087
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('scores', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: passes
-- @bsb-block-data passes
-- @bsb-hash sha256:8ce9cd04377f76de85e1d62902a4c9015c59b4fbe8ead634899d989972b2e02b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('passes', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: billable-time
-- @bsb-block-data billable-time
-- @bsb-hash sha256:e03d1cc092ec5ad01389ac485d7354915fad1cc6732344906a9f3d41034c5eb8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('billable-time', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: leases
-- @bsb-block-data leases
-- @bsb-hash sha256:916537b0ac15a44d934f0953f1905d46b0489cbc62ee42af0d92f389f7ae4b1d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('leases', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: expenses
-- @bsb-block-data expenses
-- @bsb-hash sha256:acad5782117da37aa32eb5b47f0372cb87a9105ea9687dd5f8de16d1ca73932f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('expenses', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: donations
-- @bsb-block-data donations
-- @bsb-hash sha256:766adfa3e7067c6f8172269a3181465a320dd4dc98f6ab433fc4ba3e69980c75
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('donations', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: dispatch
-- @bsb-block-data dispatch
-- @bsb-hash sha256:06cac982f9d10a52b300a2913d8d96298562a0dc0c2043a5479ae1d6728664ef
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('dispatch', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: shipments
-- @bsb-block-data shipments
-- @bsb-hash sha256:00b866bfbfdf49e28afaca776e11cb39cfb66b84a94438dfed6465486f196d59
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('shipments', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: contracts
-- @bsb-block-data contracts
-- @bsb-hash sha256:b1a7e96abf128612c48aa98934154eba84d8f10a54de419c4b896cafe5a2a268
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('contracts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: compliance
-- @bsb-block-data compliance
-- @bsb-hash sha256:67d3dd84888336cbf682232658334fb5fcaafe1da10d3a7369c5a1846452533f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."notification_events"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."notification_events" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."notification_subscriptions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."notification_subscriptions" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."guest_grants"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."guest_grants" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."attachments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."attachments" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."data_exports"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."data_exports" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."enrollments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."enrollments" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."workflow_runs"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."workflow_runs" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."workflow_start_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."workflow_start_requests" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."knowledge_documents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."knowledge_documents" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."memories"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."memories" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."taggings"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."taggings" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."status_history"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."status_history" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."status_stages"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."status_stages" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_lifecycles"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_lifecycles" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."field_values"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."field_values" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."share_links"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."share_links" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_views"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_views" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_user_state"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_user_state" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."recurrence_rules"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."recurrence_rules" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reminders"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reminders" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."import_records"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."import_records" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_members"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_members" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."relations"') and attname = 'source_type' and not attisdropped) then update "better_supabase"."relations" set "source_type" = 'compliance_policy' where "source_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."relations"') and attname = 'target_type' and not attisdropped) then update "better_supabase"."relations" set "target_type" = 'compliance_policy' where "target_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."bulk_runs"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."bulk_runs" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."search_documents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."search_documents" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."calendar_events"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."calendar_events" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."calendar_attendees"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."calendar_attendees" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."versions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."versions" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."trash_items"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."trash_items" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reactions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reactions" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reaction_scores"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reaction_scores" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."approval_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."approval_requests" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."approval_policies"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."approval_policies" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."access_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."access_requests" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."documents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."documents" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."form_submissions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."form_submissions" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."signature_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."signature_requests" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."time_entries"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."time_entries" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."template_applications"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."template_applications" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipelines"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipelines" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipeline_stage_history"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipeline_stage_history" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."engagement_subjects"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."engagement_subjects" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."sla_policies"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."sla_policies" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."sla_clocks"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."sla_clocks" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."moderation_items"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."moderation_items" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."automations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."automations" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."automation_defaults"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."automation_defaults" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."automation_evaluations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."automation_evaluations" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."automation_fields"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."automation_fields" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."score_models"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."score_models" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."scores"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."scores" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."passes"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."passes" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."work_orders"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."work_orders" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."shipments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."shipments" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."conversations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."conversations" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."message_record_mentions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."message_record_mentions" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."channels"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."channels" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."timeline_entries"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."timeline_entries" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."mail_thread_subjects"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."mail_thread_subjects" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."segments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."segments" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."assignment_queues"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."assignment_queues" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."assignments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."assignments" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."field_changes"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."field_changes" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."lead_score_checks"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."lead_score_checks" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."qualification_requirements"') and attname = 'target_type' and not attisdropped) then update "better_supabase"."qualification_requirements" set "target_type" = 'compliance_policy' where "target_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."acknowledgement_assignments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."acknowledgement_assignments" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."acknowledgements"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."acknowledgements" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."acknowledgement_notices"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."acknowledgement_notices" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."consents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."consents" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."observations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."observations" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."medication_orders"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."medication_orders" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."care_plans"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."care_plans" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."bank_matches"') and attname = 'target_type' and not attisdropped) then update "better_supabase"."bank_matches" set "target_type" = 'compliance_policy' where "target_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."funding_awards"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."funding_awards" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."funding_deliveries"') and attname = 'source_type' and not attisdropped) then update "better_supabase"."funding_deliveries" set "source_type" = 'compliance_policy' where "source_type" = 'policy'; end if; end $$;

-- Policies assigned to the member role reach every member.
do $$
begin
  if to_regclass('"better_supabase"."acknowledgement_assignments"') is null then
    return;
  end if;
  update "better_supabase"."acknowledgement_assignments" x
  set "principal_id" = '*'
  where x."subject_type" = 'compliance_policy'
    and x."principal_type" = 'role'
    and x."principal_id" = 'member'
    and not exists (
      select 1 from "better_supabase"."acknowledgement_assignments" y
      where y."tenant_id" = x."tenant_id"
        and y."subject_type" = x."subject_type"
        and y."subject_id" = x."subject_id"
        and y."principal_type" = 'role'
        and y."principal_id" = '*'
    );
end;
$$;

insert into better_supabase.blocks (name, version, mode)
values ('compliance', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: incidents
-- @bsb-block-data incidents
-- @bsb-hash sha256:52bbfcfc58f60eda6824df5900cda640c660b7c55adb67cd2e240a93c367c892
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('incidents', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: courses
-- @bsb-block-data courses
-- @bsb-hash sha256:be2ff5b96a994fd2b818c43f00e4213d79617735d6840d20eaac3479c0b564b5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('courses', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: messaging
-- @bsb-block-data messaging
-- @bsb-hash sha256:f6f663ad751dca539974d5acd6bfa3535c76b9f8c683cccee28ef362685c9b84
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('messaging', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: channels
-- @bsb-block-data channels
-- @bsb-hash sha256:235ba24a4cb73e5c97210335a1509205dbcc924ac9a205f879979dbcb86375c2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('channels', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: timeline
-- @bsb-block-data timeline
-- @bsb-hash sha256:0299e571a21a6e13782036c73dc69c5ea027002fee25486ca10e521b53049317
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Event types renamed by the 0.47 naming convention (ADR 0130).
update "better_supabase"."timeline_entries" t set "type" = m.next_type
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
  ('sequence_enrollment.completed', 'enrollment.completed'),
  ('sequence_enrollment.created', 'enrollment.created'),
  ('sequence_enrollment.exited', 'enrollment.cancelled'),
  ('sequence_enrollment.paused', 'enrollment.paused'),
  ('sequence_enrollment.resumed', 'enrollment.resumed'),
  ('sequence_enrollment.step_completed', 'enrollment.step_completed'),
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
  ('workflow.published', 'workflow_definition.published')
) as m(old_type, next_type)
where t."type" = m.old_type;

insert into better_supabase.blocks (name, version, mode)
values ('timeline', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: mail-sync
-- @bsb-block-data mail-sync
-- @bsb-hash sha256:a455c51c4d5ee70107696c80dad74fd5dee24dfb085ce0167490dd90eb1ef9c4
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('mail-sync', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: segments
-- @bsb-block-data segments
-- @bsb-hash sha256:f76caa6bc2fb8d61d0ab4f737a547139fcba649cfba64eedafa2b1164210a29b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('segments', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: assignment
-- @bsb-block-data assignment
-- @bsb-hash sha256:336c65d0cac5c9c18ec22385c79dea4ed6a56ebaee602d9ffd157ca812e472aa
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('assignment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: enrichment
-- @bsb-block-data enrichment
-- @bsb-hash sha256:dcb04aea5c6dba2694f8efab01af3f4faf3ae190eaf85c4f2685d756fb3f5cb1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('enrichment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: forecasts
-- @bsb-block-data forecasts
-- @bsb-hash sha256:1a236d3062db7e93bf2739b0ee553543da0d1d3546fd673f331fd49953cbf0af
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('forecasts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: field-history
-- @bsb-block-data field-history
-- @bsb-hash sha256:563bb02e577a82d70031527590e31e445260155bc6212649c68e4e88083c124f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('field-history', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: sequences
-- @bsb-block-data sequences
-- @bsb-hash sha256:882f94cc0c9f6809311120cc5646344d881689fd649d666011977bb8ccc9624a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sequences', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: lead-scoring
-- @bsb-block-data lead-scoring
-- @bsb-hash sha256:203a68f20ea218ac8f9ece257a8d1077295048204e38b54f97d5f2b29b7e24d8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('lead-scoring', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: posts
-- @bsb-block-data posts
-- @bsb-hash sha256:cf3d9eb13597345e8c143e55724f0dfbbb72694518788ae9544aa9820b826e8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('posts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: field-encryption
-- @bsb-block-data field-encryption
-- @bsb-hash sha256:d58ab41031404e1532b8554ca08a2564787cc54aa0f0be2b52af7380d697666d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('field-encryption', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: content
-- @bsb-block-data content
-- @bsb-hash sha256:78b4b31928c1c0b3a9d4eb7cb70fbd3b44101cf04a994fc6fab9c1ca23d555c3
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('content', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: qualifications
-- @bsb-block-data qualifications
-- @bsb-hash sha256:1f1ceefd448a88336e3ab139e2cfc3cbc37f1aa636a3352e739a57f2a75c507c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('qualifications', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: risks
-- @bsb-block-data risks
-- @bsb-hash sha256:c9230989b9b165e7c6a5c6270cc003d39bc7d1c14630c7d79e62a15caf694035
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('risks', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: shifts
-- @bsb-block-data shifts
-- @bsb-hash sha256:1885529dd31ecefd0b84d5f3f56b949fcd6011a51a38cbeec6dd8c7bf0fc1545
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('shifts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: accounting
-- @bsb-block-data accounting
-- @bsb-hash sha256:51851417a9dc349b1d7c5a2e3bd03d12ebf0417519b093f85ae57b6e24866f4a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Adds the disposal gain and loss accounts to existing charts of accounts.
insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable")
select s."tenant_id", c.code, c.name, c.type, c.subtype, false
from "better_supabase"."accounting_settings" s
cross join (values ('disposal_gain', '4910', 'Gains on asset disposals', 'income', 'other_income'), ('disposal_loss', '6910', 'Losses on asset disposals', 'expense', 'other_expense')) c (role, code, name, type, subtype)
where exists (select 1 from "better_supabase"."accounting_accounts" y where y."tenant_id" = s."tenant_id")
  and not exists (select 1 from "better_supabase"."accounting_account_roles" z where z."tenant_id" = s."tenant_id" and z."role" = c.role)
  and not exists (select 1 from "better_supabase"."accounting_accounts" y where y."tenant_id" = s."tenant_id" and y."code" = c.code);
insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
select s."tenant_id", c.role, y."id"
from "better_supabase"."accounting_settings" s
cross join (values ('disposal_gain', '4910', 'Gains on asset disposals'), ('disposal_loss', '6910', 'Losses on asset disposals')) c (role, code, name)
join "better_supabase"."accounting_accounts" y on y."tenant_id" = s."tenant_id" and y."code" = c.code and y."name" = c.name
where not exists (select 1 from "better_supabase"."accounting_account_roles" z where z."tenant_id" = s."tenant_id" and z."role" = c.role)
on conflict ("tenant_id", "role") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('accounting', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: acknowledgements
-- @bsb-block-data acknowledgements
-- @bsb-hash sha256:f804dc1bd56a250af2771946adc718a33fc2dbcbbb8cd45180ca0480d6b11329
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('acknowledgements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: consents
-- @bsb-block-data consents
-- @bsb-hash sha256:847489b2aac958461d00305ddc46b04b6f03efe6f788452507bf88a805895ea4
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('consents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: observations
-- @bsb-block-data observations
-- @bsb-hash sha256:15b68d26cf29d7a6ab506771f194c4125667d9ec17bcc98190ed785ca39060fc
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- blocks.observations.options.defaults: the vital signs, as system
-- definitions every organization reads.
insert into "better_supabase"."observation_definitions" ("tenant_id", "key", "title", "value_type", "unit", "code_system", "code", "components", "decimals", "valid_low", "valid_high", "reference_low", "reference_high", "critical_low", "critical_high")
values
  (null, 'heart_rate', 'Heart rate', 'integer', '/min', 'http://loinc.org', '8867-4', null, null, 0, 350, 51, 90, 40, 131),
  (null, 'blood_pressure', 'Blood pressure', 'components', null, 'http://loinc.org', '85354-9', '[{"key":"systolic","title":"Systolic","unit":"mm[Hg]","code":"8480-6","validLow":0,"validHigh":350,"referenceLow":100,"referenceHigh":140,"criticalLow":90,"criticalHigh":220}, {"key":"diastolic","title":"Diastolic","unit":"mm[Hg]","code":"8462-4","validLow":0,"validHigh":250,"referenceLow":60,"referenceHigh":90,"criticalLow":40,"criticalHigh":130}]'::jsonb, null, null, null, null, null, null, null),
  (null, 'body_temperature', 'Body temperature', 'number', 'Cel', 'http://loinc.org', '8310-5', null, 1, 20, 46, 36.1, 38, 35, 39.1),
  (null, 'respiratory_rate', 'Respiratory rate', 'integer', '/min', 'http://loinc.org', '9279-1', null, null, 0, 100, 12, 20, 8, 25),
  (null, 'oxygen_saturation', 'Oxygen saturation', 'integer', '%', 'http://loinc.org', '2708-6', null, null, 0, 100, 96, null, 91, null),
  (null, 'body_weight', 'Body weight', 'number', 'kg', 'http://loinc.org', '29463-7', null, 1, 0, 700, null, null, null, null),
  (null, 'body_height', 'Body height', 'number', 'cm', 'http://loinc.org', '8302-2', null, 1, 0, 300, null, null, null, null),
  (null, 'pain_score', 'Pain score', 'integer', '{score}', 'http://loinc.org', '72514-3', null, null, 0, 10, null, 3, null, null),
  (null, 'blood_glucose', 'Blood glucose', 'number', 'mmol/L', 'http://loinc.org', '15074-8', null, 1, 0, 60, 4, 7.8, 3, 20)
on conflict ("tenant_id", "key") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('observations', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: medications
-- @bsb-block-data medications
-- @bsb-hash sha256:5a31b4489eba3fccd92a203fd47e002c98354a7226595d3ed756da092d3c5994
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('medications', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: care-plans
-- @bsb-block-data care-plans
-- @bsb-hash sha256:34a4d6e1f181a5c140dcd50eb8a2994ffa2f7f8a4fca1661583b103e5da02950
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('care-plans', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: inspections
-- @bsb-block-data inspections
-- @bsb-hash sha256:2c877d673ffd6dbad827ec793bfa52d6ad605faaec97307b2daabb490a96d99f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inspections', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: manufacturing
-- @bsb-block-data manufacturing
-- @bsb-hash sha256:18e97e8f7006d8439ff170eb5ff50bad4ae04bd0bce4957faa697bb6da3b3dd2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('manufacturing', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: banking
-- @bsb-block-data banking
-- @bsb-hash sha256:0104094d35c4212d5c0d1245406934860479cf630e6eb25c1d97901403901c73
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('banking', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: meetings
-- @bsb-block-data meetings
-- @bsb-hash sha256:d31cbf2e018d65bfd29e91b50d5c2732ada972c444c0320c57445f6ebe6a41f6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('meetings', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: legal-entities
-- @bsb-block-data legal-entities
-- @bsb-hash sha256:2f562e0fc37b73534d82eec86c0b9b2fbd8131c55be9ab68dee46882609313a6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('legal-entities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: funding
-- @bsb-block-data funding
-- @bsb-hash sha256:5f2aaa76a9d6c8414def54826e938bc7edcce178f14b0d9edd894653bfab3d11
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('funding', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
