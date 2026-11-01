-- better-supabase add --adopt: the rows and settings of updated-at, audit, memberships, invitations, queue, realtime-tables, jsonb-schemas, grants, read-sets, entitlements, rate-limit, vector-search, permissions, organizations, profiles, outbox, notifications, webhooks-out, sessions, api-keys, settings, usage, flags, drive, guests, comments, attachments, data-lifecycle, sso, enrollments, onboarding, waitlist, announcements, streams, credentials, workflows, workflow-sdk, workflow-editor, chat-sdk-state, inbox, ai-chat, ai-files, knowledge, memory, agents, connectors, ai-schedules, push, ai-cache, ai-keys, numbering, teams, tags, state-machine, custom-fields, share-links, reminders, imports, subjects, rank, saved-views, relations, bulk, catalog, search, metrics, calendar, bookings, versions, trash, reactions, approvals, access-requests, documents, ledger, inventory, drive-files, orders, promotions, forms, signatures, time-tracking, service-accounts, templates, cases, deals, hiring, tasks, tasks, pipelines, contacts, activities, quotes, invoices, sla, goals, employees, signing-keys, moderation, automations, assets, scores, passes, billable-time, leases, expenses, donations, dispatch, shipments, contracts, compliance, incidents, courses, messaging, channels, timeline, mail-sync, segments, assignment, enrichment, forecasts, field-history, sequences, lead-scoring, posts, field-encryption, content, qualifications, risks, shifts, tax, accounting, acknowledgements, consents, observations, medications, care-plans, inspections, manufacturing, banking, meetings, legal-entities, funding, payroll-export, maintenance, dam, document-templates, lims, appraisals, warehouse, rfqs, tills, clinical-decision-support, which a schema diff skips.

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
-- @bsb-hash sha256:7916d0f26225eba592dd8fc0851ccded54e813ab4ce97905a5f0dff43ef68012
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

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.webhook_endpoints', target_type => 'webhook_endpoint', event_prefix => 'webhook_endpoint', deferred => true);

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
-- @bsb-hash sha256:4e455e11e2f396b5918263f01f7e35717fcfccaf9f98103152327d0652a07b8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.api_keys', target_type => 'api_key', event_prefix => 'api_key', deferred => true);

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
-- @bsb-hash sha256:1fcf6e4a3cf9cc3d8086e00a92129a0a1ac2a099d12130a3d108f626ece0af00
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.flags', target_type => 'flag', event_prefix => 'flag', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('flags', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: drive
-- @bsb-block-data drive
-- @bsb-hash sha256:23c2a6ccc1ffbc453bc0c6ede3924ce3127c7a0b62cd6d32fb6b49a0aec25820
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.drive_nodes', target_type => 'drive_node', event_prefix => 'drive_node', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('drive', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: guests
-- @bsb-block-data guests
-- @bsb-hash sha256:dced392f17ba7c319610f3dac193505ba8b94dd6bac885fb9ad100284945e077
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.guests', target_type => 'guest', event_prefix => 'guest', deferred => true);
select better_supabase.audit('better_supabase.guest_grants', target_type => 'guest_grant', event_prefix => 'guest_grant', deferred => true);

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
-- @bsb-hash sha256:8bdaf0a7ad6cad1fafaa63f09c2777ce7fbd1fee33d6ccc768e4b854c232f591
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 52428800, null)
on conflict (id) do update set public = excluded.public;

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.attachments', target_type => 'attachment', event_prefix => 'attachment', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('attachments', 8, 'managed')
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
-- @bsb-hash sha256:f3c43f8528dd0330050009a7308139919a3338a8ac84e4a97985d138aea823c5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.enrollment_programs', target_type => 'enrollment_program', event_prefix => 'enrollment_program', deferred => true);
select better_supabase.audit('better_supabase.enrollments', target_type => 'enrollment', event_prefix => 'enrollment', deferred => true);

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
-- @bsb-hash sha256:029604f136d5df8183e09e8aa760cd6a295266eaa6217ee1cd19a6425e6dc975
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.waitlist_entries', target_type => 'waitlist_entry', event_prefix => 'waitlist_entry', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('waitlist', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: announcements
-- @bsb-block-data announcements
-- @bsb-hash sha256:a7c59a8035fae5fac0fb10bfed79e91e2989caf12ede2d22f941b3858b3a924e
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.announcements', target_type => 'announcement', event_prefix => 'announcement', deferred => true);

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
-- @bsb-hash sha256:48d23d636108a6736858445513953a952725ba18d63d46926b29ba1251c8e8fe
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.workflow_definitions', target_type => 'workflow_definition', event_prefix => 'workflow_definition', deferred => true);

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
-- @bsb-hash sha256:4d349c0c75ea101102a2ea37caa240bbf52f32ba02a2246f35879565e54ccc94
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "better_supabase"."automation_defaults" ("key", "block", "subject_type", "trigger", "name", "description", "actions", "enabled")
values ('inbox.conversation_to_task', 'inbox', 'inbox_conversation', 'inbox_conversation.opened', 'Open a task for each new conversation', 'Creates a task from the conversation''s subject and preview, assigned to the conversation''s assignee and linked created_from the conversation.', '[{"kind":"tasks.from_conversation","config":{"targetType":"work_item"}}]'::jsonb, true)
on conflict ("key") do update set "subject_type" = excluded."subject_type", "trigger" = excluded."trigger", "name" = excluded."name", "description" = excluded."description", "actions" = excluded."actions", "enabled" = excluded."enabled", "block" = excluded."block", "updated_at" = now();

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.inboxes', target_type => 'inbox', event_prefix => 'inbox', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('inbox', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: ai-chat
-- @bsb-block-data ai-chat
-- @bsb-hash sha256:65b54053003f0bb6c6ae306cfe5ce799174a7213709e12ca2eec97a945dedf07
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.ai_chats', target_type => 'ai_chat', event_prefix => 'ai_chat', deferred => true);
select better_supabase.audit('better_supabase.ai_projects', target_type => 'ai_project', event_prefix => 'ai_project', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('ai-chat', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: ai-files
-- @bsb-block-data ai-files
-- @bsb-hash sha256:0cce10b60a462b023b8d67a4819a819b6c4c94751e9fbf99b6f83a7a9044968c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ai-files', 'ai-files', false, 52428800, null)
on conflict (id) do nothing;

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.ai_documents', target_type => 'ai_document', event_prefix => 'ai_document', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('ai-files', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: knowledge
-- @bsb-block-data knowledge
-- @bsb-hash sha256:05390facbd6a73f50cdf4f37accedc1a3c1857d32964872afe53b4c67a940e04
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.knowledge_documents', target_type => 'knowledge_document', event_prefix => 'knowledge_document', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('knowledge', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: memory
-- @bsb-block-data memory
-- @bsb-hash sha256:8fa217c66b59ec0ddeaadbd7b7660889e297fd1a5bbe3c8940422f04d358c450
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.memories', target_type => 'memory', event_prefix => 'memory', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('memory', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: agents
-- @bsb-block-data agents
-- @bsb-hash sha256:0c82477b580c6aaebe21d119c34bbf197ecdc306f895b8c70cb85dab84bff208
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.agents', target_type => 'agent', event_prefix => 'agent', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('agents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: connectors
-- @bsb-block-data connectors
-- @bsb-hash sha256:f50f2079acb580432a9e5891d777c803ebd103314e3c59eb49d8f42bee0c3a0f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.connector_servers', target_type => 'connector_server', event_prefix => 'connector_server', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('connectors', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: ai-schedules
-- @bsb-block-data ai-schedules
-- @bsb-hash sha256:37751e76a56127dce1317f0c78477e81a04fdbe666b931bb31963b30dc43d93b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.ai_scheduled_tasks', target_type => 'ai_scheduled_task', event_prefix => 'ai_scheduled_task', deferred => true);

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
-- @bsb-hash sha256:af0781564dfd49e1eea7753d2287f72934866bb6541918fb9238d95aae9fb425
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.teams', target_type => 'team', event_prefix => 'team', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('teams', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: tags
-- @bsb-block-data tags
-- @bsb-hash sha256:4a538cb00afa1154676f39e52532164e88416b6ba1d30e3c1dc6425a7b495b0a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.tags', target_type => 'tag', event_prefix => 'tag', deferred => true);

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
-- @bsb-hash sha256:d821d36fc5eda28c77c14382808495b444beebbddd0b01f2df822abaf1256de2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.field_definitions', target_type => 'field_definition', event_prefix => 'field_definition', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: share-links
-- @bsb-block-data share-links
-- @bsb-hash sha256:a8d7ab710f684c66f6de4c2d5cb0e4cda58005bfcfdc8cf8772fe4e81ef83180
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.share_links', target_type => 'share_link', event_prefix => 'share_link', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('share-links', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: reminders
-- @bsb-block-data reminders
-- @bsb-hash sha256:9a018c1f68e5f775dd43dad880f158928c22cf2839fb5f278b4cdc28a2414185
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.reminders', target_type => 'reminder', event_prefix => 'reminder', deferred => true);

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
-- @bsb-hash sha256:7ed0d893bd38be86750cfebdd6ab7b24e9b593922fed0dce6635058caf6505c0
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.shared_views', target_type => 'saved_view', event_prefix => 'saved_view', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('saved-views', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: relations
-- @bsb-block-data relations
-- @bsb-hash sha256:53185b4dab3db1d1eb9dec6040f33ce7e2ab13789640b8919e52bd7863a2327f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.relations', target_type => 'relation', event_prefix => 'relation', deferred => true);

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
-- @bsb-hash sha256:073fa2f24c3f7340b5b6b5290b272640b6b4f640a65f2e34c1788e26fc6dc969
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.products', target_type => 'product', event_prefix => 'product', deferred => true);
select better_supabase.audit('better_supabase.product_variants', target_type => 'product_variant', event_prefix => 'product_variant', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('catalog', 6, 'managed')
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
-- @bsb-hash sha256:4d8dd7e441db819c4e13867c386a86b4100e19b62d27e6ee55671c376504be23
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.calendar_events', target_type => 'calendar_event', event_prefix => 'calendar_event', deferred => true);
select better_supabase.audit('better_supabase.calendars', target_type => 'calendar', event_prefix => 'calendar', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('calendar', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: bookings
-- @bsb-block-data bookings
-- @bsb-hash sha256:0be24b86857b4b3165acfc8d27e3ffaa1c7b5d0b543aabc07711c4b24a581415
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.bookings', target_type => 'booking', event_prefix => 'booking', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('bookings', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: versions
-- @bsb-block-data versions
-- @bsb-hash sha256:2f421fedc5066967515c63e92fba372b1c7e39c78074a974dc621ef6bd6c4510
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.versions', target_type => 'version', event_prefix => 'version', deferred => true);

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
-- @bsb-hash sha256:cc19685ca3c64ff6c3e3e6de0c1ffd2193fc1c3d0f79cba5f8d00a7895f780e9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.reactions', target_type => 'reaction', event_prefix => 'reaction', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('reactions', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: approvals
-- @bsb-block-data approvals
-- @bsb-hash sha256:d39f755ab0f5f5d08a01e3cd24ae002907a27d0753b668123f29795c850bedac
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.approval_requests', target_type => 'approval', event_prefix => 'approval', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('approvals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: access-requests
-- @bsb-block-data access-requests
-- @bsb-hash sha256:36b60c1acda18eb860ae84fe89060b9312bad9bf644a1a7e514bd2b2f536527a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.access_requests', target_type => 'access_request', event_prefix => 'access_request', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('access-requests', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: documents
-- @bsb-block-data documents
-- @bsb-hash sha256:0e762a96f332ee03702c06a05d8ca9cbf1efc7db31968099740b0944d0d8acb5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.documents', target_type => 'document', event_prefix => 'document', deferred => true);
select better_supabase.audit('better_supabase.document_suggestions', target_type => 'document_suggestion', event_prefix => 'document_suggestion', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('documents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: ledger
-- @bsb-block-data ledger
-- @bsb-hash sha256:90addac4d2e916c61bfa5c0644276aa3b3f57e3c2d62590a1b387072a2a47a30
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.ledger_accounts', target_type => 'ledger_account', event_prefix => 'ledger_account', deferred => true);
select better_supabase.audit('better_supabase.ledger_transactions', target_type => 'ledger_transaction', event_prefix => 'ledger_transaction', deferred => true);
select better_supabase.audit('better_supabase.ledger_holds', target_type => 'ledger_hold', event_prefix => 'ledger_hold', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('ledger', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: inventory
-- @bsb-block-data inventory
-- @bsb-hash sha256:1d4193290ceda01d5b5dab87bf27e89240258af98cd13f4882776575fa53e886
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.inventory_locations', target_type => 'inventory_location', event_prefix => 'inventory_location', deferred => true);
select better_supabase.audit('better_supabase.purchase_orders', target_type => 'purchase_order', event_prefix => 'purchase_order', deferred => true);
select better_supabase.audit('better_supabase.purchase_requisitions', target_type => 'purchase_requisition', event_prefix => 'purchase_requisition', deferred => true);
select better_supabase.audit('better_supabase.inventory_receipts', target_type => 'inventory_receipt', event_prefix => 'inventory_receipt', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('inventory', 5, 'managed')
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
-- @bsb-hash sha256:ce6086bafab8841889667391c2a5c3588293525647143c140ef883866a88e31b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.orders', target_type => 'order', event_prefix => 'order', deferred => true);
select better_supabase.audit('better_supabase.carts', target_type => 'cart', event_prefix => 'cart', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('orders', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: promotions
-- @bsb-block-data promotions
-- @bsb-hash sha256:f9da48589401e931c35cba5a3ad4fd01a3f55cb0b9cf9b2827b098a886b072dc
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.promotions', target_type => 'promotion', event_prefix => 'promotion', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('promotions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: forms
-- @bsb-block-data forms
-- @bsb-hash sha256:8e99a94610f4c467685597591c474373e790f006e3cfe57ff10fea1f360011e9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.forms', target_type => 'form', event_prefix => 'form', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('forms', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: signatures
-- @bsb-block-data signatures
-- @bsb-hash sha256:fd9e09efd53e6f9147a8545444b2a1b699c830304cc7ff4adc37234d1976057a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.signature_requests', target_type => 'signature_request', event_prefix => 'signature_request', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('signatures', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: time-tracking
-- @bsb-block-data time-tracking
-- @bsb-hash sha256:c6d1cd3ca463ac0703d56fe4a6025fa8212d2c79603642dd75d9c94291e44ba3
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.time_entries', target_type => 'time_entry', event_prefix => 'time_entry', deferred => true);
select better_supabase.audit('better_supabase.timesheets', target_type => 'timesheet', event_prefix => 'timesheet', deferred => true);

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
-- @bsb-hash sha256:23e698b4a62dc6f05efc7081ffc9dee2af054e6f9c1329921f5ab2f2a07adce4
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.templates', target_type => 'template', event_prefix => 'template', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('templates', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: cases
-- @bsb-block-data cases
-- @bsb-hash sha256:c35f9f117664486d222ee7c239990212bfa05568b858028b5621537641ec3332
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.cases', target_type => 'case', event_prefix => 'case', deferred => true);
select better_supabase.audit('better_supabase.case_kinds', target_type => 'case_kind', event_prefix => 'case_kind', deferred => true);
select better_supabase.audit('better_supabase.case_actions', target_type => 'case_action', event_prefix => 'case_action', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('cases', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: deals
-- @bsb-block-data deals
-- @bsb-hash sha256:49c83bad4d4b53c4051e1d5ebc7fefa63bd25abd0c9109519f21f622fd4aed58
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.deals', target_type => 'deal', event_prefix => 'deal', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('deals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: hiring
-- @bsb-block-data hiring
-- @bsb-hash sha256:91d93ed4b11073d769fc6fcd6dd7763b8368dd0efcdd4615dcc32f9841216d07
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "better_supabase"."automation_defaults" ("key", "block", "subject_type", "trigger", "name", "description", "actions", "enabled")
values ('hiring.application_to_employee', 'hiring', 'application', 'application.hired', 'Preboard each hired candidate', 'Creates an employee in preboarding from the hired application''s candidate and job, linked created_from the application.', '[{"kind":"employees.from_application","config":{"targetType":"employee"}}]'::jsonb, true)
on conflict ("key") do update set "subject_type" = excluded."subject_type", "trigger" = excluded."trigger", "name" = excluded."name", "description" = excluded."description", "actions" = excluded."actions", "enabled" = excluded."enabled", "block" = excluded."block", "updated_at" = now();

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.job_openings', target_type => 'job_opening', event_prefix => 'job_opening', deferred => true);
select better_supabase.audit('better_supabase.applications', target_type => 'application', event_prefix => 'application', deferred => true);
select better_supabase.audit('better_supabase.interviews', target_type => 'interview', event_prefix => 'interview', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('hiring', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: tasks
-- @bsb-block-data tasks
-- @bsb-hash sha256:eecfb8553cd55c3effdf5a38bbc7b033ea15ab082b37125b279f34508c37b05b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Gives each existing project its value of the accounting project dimension.
select "better_supabase"."accounting_sync_dimension_value"(x."tenant_id", 'project', 'Project', x."id"::text, x."key" || ' ' || x."name", x."archived_at" is not null)
from "better_supabase"."work_projects" x
where exists (select 1 from "better_supabase"."accounting_settings" s where s."tenant_id" = x."tenant_id");

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.work_items', target_type => 'task', event_prefix => 'task', deferred => true);
select better_supabase.audit('better_supabase.work_projects', target_type => 'project', event_prefix => 'project', deferred => true);
select better_supabase.audit('better_supabase.iterations', target_type => 'iteration', event_prefix => 'iteration', deferred => true);
select better_supabase.audit('better_supabase.work_item_checklist_items', target_type => 'checklist_item', event_prefix => 'checklist_item', deferred => true);

-- Realtime for the module's entities (subject.realtime)
select better_supabase.track_realtime('better_supabase.work_items', tenant_column => 'tenant_id');

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: facilities
-- @bsb-block-data facilities
-- @bsb-hash sha256:ec467c4ab976d5aa915b100d4bf1f2ec30d30f63b743b8d539ccd5ca07de4d74
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.maintenance_requests', target_type => 'task', event_prefix => 'task', deferred => true);
select better_supabase.audit('better_supabase.maintenance_request_checklist_items', target_type => 'checklist_item', event_prefix => 'checklist_item', deferred => true);

-- Realtime for the module's entities (subject.realtime)
select better_supabase.track_realtime('better_supabase.maintenance_requests', tenant_column => 'tenant_id');

alter table better_supabase.blocks add column if not exists block text;
insert into better_supabase.blocks (name, block, version, mode)
values ('facilities', 'tasks', 4, 'managed')
on conflict (name) do update
  set block = excluded.block, version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: pipelines
-- @bsb-block-data pipelines
-- @bsb-hash sha256:500735436af3b07e078f741b31c4b5cbfb52786b147142e567a3ddae0bcaa2bc
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.pipelines', target_type => 'pipeline', event_prefix => 'pipeline', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('pipelines', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: contacts
-- @bsb-block-data contacts
-- @bsb-hash sha256:c5f2eb5e5df84c0f9c5ec31500d003e5348e8859fca006ee0be39d557d583f3f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.companies', target_type => 'company', event_prefix => 'company', deferred => true);
select better_supabase.audit('better_supabase.people', target_type => 'person', event_prefix => 'person', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('contacts', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: activities
-- @bsb-block-data activities
-- @bsb-hash sha256:ca9a162c0440f6cd829fa170374245c43e19bef80a53ea6028c687cb5fb2dc6a
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
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."care_alerts"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."care_alerts" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.activities', target_type => 'activity', event_prefix => 'activity', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('activities', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: quotes
-- @bsb-block-data quotes
-- @bsb-hash sha256:1826d38ca72e944d283ac6908067a101336d0a9bd52ed66fc174f8244994ed6a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "better_supabase"."automation_defaults" ("key", "block", "subject_type", "trigger", "name", "description", "actions", "enabled")
values ('quotes.quote_to_order', 'quotes', 'quote', 'quote.accepted', 'Order each accepted quote', 'Creates an order for the accepted quote, linked created_from the quote, so an accepted quote orders once.', '[{"kind":"orders.from_quote","config":{"targetType":"order"}}]'::jsonb, false)
on conflict ("key") do update set "subject_type" = excluded."subject_type", "trigger" = excluded."trigger", "name" = excluded."name", "description" = excluded."description", "actions" = excluded."actions", "enabled" = excluded."enabled", "block" = excluded."block", "updated_at" = now();

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.quotes', target_type => 'quote', event_prefix => 'quote', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('quotes', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: invoices
-- @bsb-block-data invoices
-- @bsb-hash sha256:e18fc61ff94e7b7178a4a1cbb8685d15b7aada2f5858bea4b64848f74c7c7178
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.invoices', target_type => 'invoice', event_prefix => 'invoice', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('invoices', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: sla
-- @bsb-block-data sla
-- @bsb-hash sha256:cb39685a0e9441caa3a35d8177532ca7a9814b961931afd002f80228fc966ae3
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.sla_policies', target_type => 'sla_policy', event_prefix => 'sla_policy', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('sla', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: goals
-- @bsb-block-data goals
-- @bsb-hash sha256:133e146efcb0b66f16e26b67e1184e05bc36eb015d59ef68b62c4318450da573
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.goals', target_type => 'goal', event_prefix => 'goal', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('goals', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: employees
-- @bsb-block-data employees
-- @bsb-hash sha256:a2103a2f544c56153b3bea07cbbe2a0a422c610c3c939ee72de05ec2d22aca91
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.employees', target_type => 'employee', event_prefix => 'employee', deferred => true);

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
-- @bsb-hash sha256:755a622e513363a5ad764ac2121afcc8138e5ff9fc3e1233cda4714f79881159
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.moderation_items', target_type => 'moderation_item', event_prefix => 'moderation_item', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('moderation', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: automations
-- @bsb-block-data automations
-- @bsb-hash sha256:9f6064189a8311803bfed8748076a9b4fcc67f7032810749f95a269d2c8b4754
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

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.automations', target_type => 'automation', event_prefix => 'automation', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('automations', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: assets
-- @bsb-block-data assets
-- @bsb-hash sha256:4b95cfa6067a3d116a52cc1c6dcfd2e264743b243404cf61a1ac255a641b3937
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "postgis" with schema "extensions";

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.assets', target_type => 'asset', event_prefix => 'asset', deferred => true);
select better_supabase.audit('better_supabase.asset_locations', target_type => 'asset_location', event_prefix => 'asset_location', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('assets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: scores
-- @bsb-block-data scores
-- @bsb-hash sha256:810f775915ea54b780507f9dd8604dd208be9bca5ef0f3a6f1d31df45d8a280c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.score_models', target_type => 'score_model', event_prefix => 'score_model', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('scores', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: passes
-- @bsb-block-data passes
-- @bsb-hash sha256:63104499c4208ff7874aced5ab8d8a28f09c586f98d34c01bcba2fc2e1f5c499
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.passes', target_type => 'pass', event_prefix => 'pass', deferred => true);
select better_supabase.audit('better_supabase.pass_check_ins', target_type => 'pass_check_in', event_prefix => 'pass_check_in', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('passes', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: billable-time
-- @bsb-block-data billable-time
-- @bsb-hash sha256:bb694d5756c1ea856e4290ed263079a40a6d539f659d79ec614b55988fa01ab0
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.time_rates', target_type => 'time_rate', event_prefix => 'time_rate', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('billable-time', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: leases
-- @bsb-block-data leases
-- @bsb-hash sha256:17f0b5a80753a2f0776de9f117d072bdbcc1caecbb89d85c7f20fc15008f9a76
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.leases', target_type => 'lease', event_prefix => 'lease', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('leases', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: expenses
-- @bsb-block-data expenses
-- @bsb-hash sha256:4bb15b3dc7b3519077541886245e20b0585fcd2a0be14886b47311e20fc85d54
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.expense_reports', target_type => 'expense_report', event_prefix => 'expense_report', deferred => true);
select better_supabase.audit('better_supabase.expense_lines', target_type => 'expense_line', event_prefix => 'expense_line', deferred => true);
select better_supabase.audit('better_supabase.expense_categories', target_type => 'expense_category', event_prefix => 'expense_category', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('expenses', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: donations
-- @bsb-block-data donations
-- @bsb-hash sha256:16f1acb7c5d7b4939d5b1ede742178ea14dc0129b25739202d47f15536f3710c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.donations', target_type => 'donation', event_prefix => 'donation', deferred => true);
select better_supabase.audit('better_supabase.pledges', target_type => 'pledge', event_prefix => 'pledge', deferred => true);
select better_supabase.audit('better_supabase.donation_funds', target_type => 'donation_fund', event_prefix => 'donation_fund', deferred => true);
select better_supabase.audit('better_supabase.donation_receipts', target_type => 'donation_receipt', event_prefix => 'donation_receipt', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('donations', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: dispatch
-- @bsb-block-data dispatch
-- @bsb-hash sha256:566449ba8b3de587164ff69f0f38840f80118679db3881bd096d78c5050171cb
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.work_orders', target_type => 'work_order', event_prefix => 'work_order', deferred => true);
select better_supabase.audit('better_supabase.dispatch_routes', target_type => 'dispatch_route', event_prefix => 'dispatch_route', deferred => true);
select better_supabase.audit('better_supabase.work_order_parts', target_type => 'work_order_part', event_prefix => 'work_order_part', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('dispatch', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: shipments
-- @bsb-block-data shipments
-- @bsb-hash sha256:766ce6f17da496eb98f3fc55b02d29819491da1ed30e5f00d4fe21958f20c170
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.shipments', target_type => 'shipment', event_prefix => 'shipment', deferred => true);
select better_supabase.audit('better_supabase.shipment_packages', target_type => 'shipment_package', event_prefix => 'shipment_package', deferred => true);
select better_supabase.audit('better_supabase.shipment_tracking_events', target_type => 'shipment_tracking_event', event_prefix => 'shipment_tracking_event', deferred => true);
select better_supabase.audit('better_supabase.shipment_lines', target_type => 'shipment_line', event_prefix => 'shipment_line', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('shipments', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: contracts
-- @bsb-block-data contracts
-- @bsb-hash sha256:6f10c53545266be5593649485dde39b4db4206bfd269e0e2508052992a5cfc9f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.contracts', target_type => 'contract', event_prefix => 'contract', deferred => true);
select better_supabase.audit('better_supabase.contract_obligations', target_type => 'contract_obligation', event_prefix => 'contract_obligation', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('contracts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: compliance
-- @bsb-block-data compliance
-- @bsb-hash sha256:d0f4549a12a5d5685bbd1e2b10a88622572fea21d8170eb202aac7935dc3f516
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
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."care_alerts"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."care_alerts" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;

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

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.controls', target_type => 'control', event_prefix => 'control', deferred => true);
select better_supabase.audit('better_supabase.control_frameworks', target_type => 'control_framework', event_prefix => 'control_framework', deferred => true);
select better_supabase.audit('better_supabase.evidence_tasks', target_type => 'evidence_task', event_prefix => 'evidence_task', deferred => true);
select better_supabase.audit('better_supabase.compliance_policies', target_type => 'compliance_policy', event_prefix => 'compliance_policy', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('compliance', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: incidents
-- @bsb-block-data incidents
-- @bsb-hash sha256:ac92b9d8b52fe4487192e0f407db610b8cfc32433b5fc3a3ce42a7ebc358f561
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.incidents', target_type => 'incident', event_prefix => 'incident', deferred => true);
select better_supabase.audit('better_supabase.incident_status_components', target_type => 'status_component', event_prefix => 'status_component', deferred => true);
select better_supabase.audit('better_supabase.incident_postmortems', target_type => 'incident_postmortem', event_prefix => 'incident_postmortem', deferred => true);
select better_supabase.audit('better_supabase.incident_status_pages', target_type => 'status_page', event_prefix => 'status_page', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('incidents', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: courses
-- @bsb-block-data courses
-- @bsb-hash sha256:54038f81ebd10cd26de9047b1aec811fd6ad5c04f81571016303c693ec9d990b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.courses', target_type => 'course', event_prefix => 'course', deferred => true);
select better_supabase.audit('better_supabase.course_modules', target_type => 'course_module', event_prefix => 'course_module', deferred => true);
select better_supabase.audit('better_supabase.course_lessons', target_type => 'course_lesson', event_prefix => 'course_lesson', deferred => true);
select better_supabase.audit('better_supabase.course_certificates', target_type => 'course_certificate', event_prefix => 'course_certificate', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('courses', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: messaging
-- @bsb-block-data messaging
-- @bsb-hash sha256:0c7b44a6331db002bc57c85f33b2758272c55ddd625ceb076b17b027a98b2966
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.messages', target_type => 'message', event_prefix => 'message', deferred => true);
select better_supabase.audit('better_supabase.conversations', target_type => 'conversation', event_prefix => 'conversation', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('messaging', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: channels
-- @bsb-block-data channels
-- @bsb-hash sha256:082f9e71f0f17e5b8e792b09320851554e48d46b125ad65388203d7028069a4f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.channels', target_type => 'channel', event_prefix => 'channel', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('channels', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: timeline
-- @bsb-block-data timeline
-- @bsb-hash sha256:4bf365955ed5335888b52c00168f67a4545311e5213c228a3b9846a3f9df8276
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

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.timeline_entries', target_type => 'timeline_entry', event_prefix => 'timeline_entry', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('timeline', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: mail-sync
-- @bsb-block-data mail-sync
-- @bsb-hash sha256:d6a123587cb645382f05a5bcf1646a69732f74274975711e06de8fdf256fc03f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.mail_threads', target_type => 'mail_thread', event_prefix => 'mail_thread', deferred => true);
select better_supabase.audit('better_supabase.mail_accounts', target_type => 'mail_account', event_prefix => 'mail_account', deferred => true);
select better_supabase.audit('better_supabase.mail_messages', target_type => 'mail_message', event_prefix => 'mail_message', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('mail-sync', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: segments
-- @bsb-block-data segments
-- @bsb-hash sha256:5efc77b1fec9aad8da02903f7301a28f486b846f3843ad99bdea56930fe19acd
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.segments', target_type => 'segment', event_prefix => 'segment', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('segments', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: assignment
-- @bsb-block-data assignment
-- @bsb-hash sha256:e27546a194847219d3e323c0023bfffc4069ddb575dc1b5742bd6ed7fcdad0e9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.assignment_queues', target_type => 'assignment_queue', event_prefix => 'assignment_queue', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('assignment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: enrichment
-- @bsb-block-data enrichment
-- @bsb-hash sha256:f576c7f34149a7dc8fc0b89e38b14b8a7f7f0f165eabf7b901696dc419879773
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.enrichments', target_type => 'enrichment', event_prefix => 'enrichment', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('enrichment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: forecasts
-- @bsb-block-data forecasts
-- @bsb-hash sha256:56fd601d3dd92737e5b575fd3f55fa5ec74d3726ac3990fa3866b5e2d52e16ef
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.forecast_snapshots', target_type => 'forecast_snapshot', event_prefix => 'forecast_snapshot', deferred => true);

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
-- @bsb-hash sha256:0e7477ca878df5210bfd1b528e079ee325e6f14489c8545afd57d5ccd6de3db7
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.sequences', target_type => 'sequence', event_prefix => 'sequence', deferred => true);

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
-- @bsb-hash sha256:e93aba4eb51441ffda738822604d46c3140f5a7ceff1b471e867cd3e2706bbb5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.post_boards', target_type => 'post_board', event_prefix => 'post_board', deferred => true);
select better_supabase.audit('better_supabase.posts', target_type => 'post', event_prefix => 'post', deferred => true);

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
-- @bsb-hash sha256:76e708a61bdb9a4d609624df66659251b66685572dc7d3231d8f4f18cf2598a7
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.content_entries', target_type => 'content_entry', event_prefix => 'content_entry', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('content', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: qualifications
-- @bsb-block-data qualifications
-- @bsb-hash sha256:650c2bd75077321a10c7aedecf9c1f5e7a4a7614cc2114b510b41e78f4ddebe8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.qualifications', target_type => 'qualification', event_prefix => 'qualification', deferred => true);
select better_supabase.audit('better_supabase.qualification_types', target_type => 'qualification_type', event_prefix => 'qualification_type', deferred => true);
select better_supabase.audit('better_supabase.qualification_requirements', target_type => 'qualification_requirement', event_prefix => 'qualification_requirement', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('qualifications', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: risks
-- @bsb-block-data risks
-- @bsb-hash sha256:d7942bd4fdbd32cae27560b35f4a24701829819cb001858a4a7eda22438ae4c4
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.risks', target_type => 'risk', event_prefix => 'risk', deferred => true);
select better_supabase.audit('better_supabase.risk_matrices', target_type => 'risk_matrix', event_prefix => 'risk_matrix', deferred => true);
select better_supabase.audit('better_supabase.risk_assessments', target_type => 'risk_assessment', event_prefix => 'risk_assessment', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('risks', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: shifts
-- @bsb-block-data shifts
-- @bsb-hash sha256:90f5aab7632a746c32b6d54486dbf09cf6d9cca59b4a5844c8c43408530bed51
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.shifts', target_type => 'shift', event_prefix => 'shift', deferred => true);
select better_supabase.audit('better_supabase.shift_templates', target_type => 'shift_template', event_prefix => 'shift_template', deferred => true);
select better_supabase.audit('better_supabase.shift_assignments', target_type => 'shift_assignment', event_prefix => 'shift_assignment', deferred => true);
select better_supabase.audit('better_supabase.shift_swaps', target_type => 'shift_swap', event_prefix => 'shift_swap', deferred => true);
select better_supabase.audit('better_supabase.shift_availability', target_type => 'shift_availability', event_prefix => 'shift_availability', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('shifts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: tax
-- @bsb-block-data tax
-- @bsb-hash sha256:f9d77d7101f4ad48002434ceb0f9c36b6daac7a217a7370f9673c6a8e2e8ce89
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.tax_codes', target_type => 'tax_code', event_prefix => 'tax_code', deferred => true);
select better_supabase.audit('better_supabase.tax_rates', target_type => 'tax_rate', event_prefix => 'tax_rate', deferred => true);
select better_supabase.audit('better_supabase.tax_returns', target_type => 'tax_return', event_prefix => 'tax_return', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('tax', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: accounting
-- @bsb-block-data accounting
-- @bsb-hash sha256:3d0316c5150b15b7a730b48a3cfcdff523aed3c83484e2dcd5f88163b806f9eb
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

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.accounting_accounts', target_type => 'accounting_account', event_prefix => 'accounting_account', deferred => true);
select better_supabase.audit('better_supabase.accounting_journals', target_type => 'accounting_journal', event_prefix => 'accounting_journal', deferred => true);
select better_supabase.audit('better_supabase.accounting_periods', target_type => 'accounting_period', event_prefix => 'accounting_period', deferred => true);
select better_supabase.audit('better_supabase.accounting_entries', target_type => 'accounting_entry', event_prefix => 'accounting_entry', deferred => true);
select better_supabase.audit('better_supabase.accounting_dimensions', target_type => 'accounting_dimension', event_prefix => 'accounting_dimension', deferred => true);
select better_supabase.audit('better_supabase.accounting_budgets', target_type => 'accounting_budget', event_prefix => 'accounting_budget', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('accounting', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: acknowledgements
-- @bsb-block-data acknowledgements
-- @bsb-hash sha256:a85a51f7724de98242442b4d1689c9d37875253e10b13364a40f59d91ae5c0a5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.acknowledgements', target_type => 'acknowledgement', event_prefix => 'acknowledgement', deferred => true);
select better_supabase.audit('better_supabase.acknowledgement_assignments', target_type => 'acknowledgement_assignment', event_prefix => 'acknowledgement_assignment', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('acknowledgements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: consents
-- @bsb-block-data consents
-- @bsb-hash sha256:4394c9ff386bb3b7bdba254f39844b9e6796de2595817774fbe313e28aa4b921
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.consents', target_type => 'consent', event_prefix => 'consent', deferred => true);
select better_supabase.audit('better_supabase.consent_purposes', target_type => 'consent_purpose', event_prefix => 'consent_purpose', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('consents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: observations
-- @bsb-block-data observations
-- @bsb-hash sha256:66751fff920e238e938902e8a21ddd2c486ad2e4e8c05e0f5c833e236bf83f16
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

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.observations', target_type => 'observation', event_prefix => 'observation', deferred => true);
select better_supabase.audit('better_supabase.observation_definitions', target_type => 'observation_definition', event_prefix => 'observation_definition', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('observations', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: medications
-- @bsb-block-data medications
-- @bsb-hash sha256:41372d590702f147c30e79d65e1ae554e2807e334a4de76caf7ebd12113351ca
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.medications', target_type => 'medication', event_prefix => 'medication', deferred => true);
select better_supabase.audit('better_supabase.medication_orders', target_type => 'medication_order', event_prefix => 'medication_order', deferred => true);
select better_supabase.audit('better_supabase.medication_administrations', target_type => 'medication_administration', event_prefix => 'medication_administration', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('medications', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: care-plans
-- @bsb-block-data care-plans
-- @bsb-hash sha256:f16daa3b5a35edb939ff9ca2e6a94f3c0bb55fbdc6d71a6e1aeceb2dbfb2389a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.care_plans', target_type => 'care_plan', event_prefix => 'care_plan', deferred => true);
select better_supabase.audit('better_supabase.care_plan_problems', target_type => 'care_plan_problem', event_prefix => 'care_plan_problem', deferred => true);
select better_supabase.audit('better_supabase.care_plan_goals', target_type => 'care_plan_goal', event_prefix => 'care_plan_goal', deferred => true);
select better_supabase.audit('better_supabase.care_plan_actions', target_type => 'care_plan_action', event_prefix => 'care_plan_action', deferred => true);
select better_supabase.audit('better_supabase.care_plan_evaluations', target_type => 'care_plan_evaluation', event_prefix => 'care_plan_evaluation', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('care-plans', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: inspections
-- @bsb-block-data inspections
-- @bsb-hash sha256:2c4ab9279a8aac170a8a54241e6d7a8324187aaaeb53650843666defd2157344
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.inspections', target_type => 'inspection', event_prefix => 'inspection', deferred => true);
select better_supabase.audit('better_supabase.inspection_programs', target_type => 'inspection_program', event_prefix => 'inspection_program', deferred => true);
select better_supabase.audit('better_supabase.inspection_findings', target_type => 'inspection_finding', event_prefix => 'inspection_finding', deferred => true);
select better_supabase.audit('better_supabase.inspection_members', target_type => 'inspection_member', event_prefix => 'inspection_member', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('inspections', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: manufacturing
-- @bsb-block-data manufacturing
-- @bsb-hash sha256:198cbaba581216c401cfe3cd3f8d8edf860ac28b2bafad8bf3bfcb84f4c2c491
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.production_orders', target_type => 'production_order', event_prefix => 'production_order', deferred => true);
select better_supabase.audit('better_supabase.boms', target_type => 'bom', event_prefix => 'bom', deferred => true);
select better_supabase.audit('better_supabase.bom_components', target_type => 'bom_component', event_prefix => 'bom_component', deferred => true);
select better_supabase.audit('better_supabase.bom_operations', target_type => 'bom_operation', event_prefix => 'bom_operation', deferred => true);
select better_supabase.audit('better_supabase.work_centers', target_type => 'work_center', event_prefix => 'work_center', deferred => true);
select better_supabase.audit('better_supabase.production_order_operations', target_type => 'production_order_operation', event_prefix => 'production_order_operation', deferred => true);
select better_supabase.audit('better_supabase.production_consumptions', target_type => 'production_consumption', event_prefix => 'production_consumption', deferred => true);
select better_supabase.audit('better_supabase.stock_lot_links', target_type => 'stock_lot_link', event_prefix => 'stock_lot_link', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('manufacturing', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: banking
-- @bsb-block-data banking
-- @bsb-hash sha256:a723e247d390d739daca9a78934d908a2a7603e82973f63a373b10fc0abbef13
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.bank_transactions', target_type => 'bank_transaction', event_prefix => 'bank_transaction', deferred => true);
select better_supabase.audit('better_supabase.bank_accounts', target_type => 'bank_account', event_prefix => 'bank_account', deferred => true);
select better_supabase.audit('better_supabase.bank_statements', target_type => 'bank_statement', event_prefix => 'bank_statement', deferred => true);
select better_supabase.audit('better_supabase.bank_matches', target_type => 'bank_match', event_prefix => 'bank_match', deferred => true);
select better_supabase.audit('better_supabase.bank_rules', target_type => 'bank_rule', event_prefix => 'bank_rule', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('banking', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: meetings
-- @bsb-block-data meetings
-- @bsb-hash sha256:be7b5dfa4e47458b3cabb7ecef25b126f2df4669a498418ef652de3714c532db
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.meetings', target_type => 'meeting', event_prefix => 'meeting', deferred => true);
select better_supabase.audit('better_supabase.meeting_attendees', target_type => 'meeting_attendee', event_prefix => 'meeting_attendee', deferred => true);
select better_supabase.audit('better_supabase.meeting_agenda_items', target_type => 'meeting_agenda_item', event_prefix => 'meeting_agenda_item', deferred => true);
select better_supabase.audit('better_supabase.meeting_decisions', target_type => 'meeting_decision', event_prefix => 'meeting_decision', deferred => true);
select better_supabase.audit('better_supabase.meeting_action_items', target_type => 'meeting_action_item', event_prefix => 'meeting_action_item', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('meetings', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: legal-entities
-- @bsb-block-data legal-entities
-- @bsb-hash sha256:ae7a1d1639f32d0d8f7ef760816a8911a32721546a710deaf670d52f5f250450
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.legal_entities', target_type => 'legal_entity', event_prefix => 'legal_entity', deferred => true);
select better_supabase.audit('better_supabase.legal_entity_settings', target_type => 'legal_entity_setting', event_prefix => 'legal_entity_setting', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('legal-entities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: funding
-- @bsb-block-data funding
-- @bsb-hash sha256:a6a2308f7e3ee5c5c7351fa0895f6e71538e61a77d2f2ea798d4b4306098a07d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.funding_products', target_type => 'funding_product', event_prefix => 'funding_product', deferred => true);
select better_supabase.audit('better_supabase.funding_awards', target_type => 'funding_award', event_prefix => 'funding_award', deferred => true);
select better_supabase.audit('better_supabase.funding_deliveries', target_type => 'funding_delivery', event_prefix => 'funding_delivery', deferred => true);
select better_supabase.audit('better_supabase.funding_claims', target_type => 'funding_claim', event_prefix => 'funding_claim', deferred => true);
select better_supabase.audit('better_supabase.funding_claim_lines', target_type => 'funding_claim_line', event_prefix => 'funding_claim_line', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('funding', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: payroll-export
-- @bsb-block-data payroll-export
-- @bsb-hash sha256:c83b874cb875b5f06f0293827e6c7f2aaa9d617bb4088ab8aec60e86d981df85
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.payroll_runs', target_type => 'payroll_run', event_prefix => 'payroll_run', deferred => true);
select better_supabase.audit('better_supabase.payroll_lines', target_type => 'payroll_line', event_prefix => 'payroll_line', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('payroll-export', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: maintenance
-- @bsb-block-data maintenance
-- @bsb-hash sha256:c5405f8bd581e3e574078225c7293446001e4c299880bcee098bca157453e5bf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.maintenance_plans', target_type => 'maintenance_plan', event_prefix => 'maintenance_plan', deferred => true);
select better_supabase.audit('better_supabase.maintenance_plan_parts', target_type => 'maintenance_plan_part', event_prefix => 'maintenance_plan_part', deferred => true);
select better_supabase.audit('better_supabase.maintenance_meters', target_type => 'maintenance_meter', event_prefix => 'maintenance_meter', deferred => true);
select better_supabase.audit('better_supabase.maintenance_meter_readings', target_type => 'maintenance_meter_reading', event_prefix => 'maintenance_meter_reading', deferred => true);
select better_supabase.audit('better_supabase.maintenance_calibrations', target_type => 'maintenance_calibration', event_prefix => 'maintenance_calibration', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('maintenance', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: dam
-- @bsb-block-data dam
-- @bsb-hash sha256:07b7ff0a13da4c61ddfc371dcc06e2f965a1fc6c13c3f7e2901e9936582d93b6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.dam_usage_rights', target_type => 'dam_usage_right', event_prefix => 'dam_usage_right', deferred => true);
select better_supabase.audit('better_supabase.dam_renditions', target_type => 'dam_rendition', event_prefix => 'dam_rendition', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('dam', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: document-templates
-- @bsb-block-data document-templates
-- @bsb-hash sha256:9583aaa09d07839093d6d62721ded388961f4622fdffe43a1e36011ffc2c8765
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.document_templates', target_type => 'document_template', event_prefix => 'document_template', deferred => true);
select better_supabase.audit('better_supabase.document_text_blocks', target_type => 'document_text_block', event_prefix => 'document_text_block', deferred => true);
select better_supabase.audit('better_supabase.rendered_documents', target_type => 'document_snapshot', event_prefix => 'document_snapshot', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('document-templates', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: lims
-- @bsb-block-data lims
-- @bsb-hash sha256:9beb6dbc0b29ce01115a2fbe7261ca42a515f17eec3ab330216c14bf716552ab
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.lims_samples', target_type => 'lims_sample', event_prefix => 'lims_sample', deferred => true);
select better_supabase.audit('better_supabase.lims_methods', target_type => 'lims_method', event_prefix => 'lims_method', deferred => true);
select better_supabase.audit('better_supabase.lims_results', target_type => 'lims_result', event_prefix => 'lims_result', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('lims', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: appraisals
-- @bsb-block-data appraisals
-- @bsb-hash sha256:b48a6852947c0e7a9e2d53342982b8193fde3d27db4480322fa77cbddebb4c99
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.appraisals', target_type => 'appraisal', event_prefix => 'appraisal', deferred => true);
select better_supabase.audit('better_supabase.appraisal_cycles', target_type => 'appraisal_cycle', event_prefix => 'appraisal_cycle', deferred => true);
select better_supabase.audit('better_supabase.appraisal_reviews', target_type => 'appraisal_review', event_prefix => 'appraisal_review', deferred => true);
select better_supabase.audit('better_supabase.appraisal_calibrations', target_type => 'appraisal_calibration', event_prefix => 'appraisal_calibration', deferred => true);
select better_supabase.audit('better_supabase.appraisal_goals', target_type => 'appraisal_goal', event_prefix => 'appraisal_goal', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('appraisals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: warehouse
-- @bsb-block-data warehouse
-- @bsb-hash sha256:7bfcff651ed4466f4db9481e0cce08a425a25213fcc8aafe7c86520749cb3602
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.pick_lists', target_type => 'pick_list', event_prefix => 'pick_list', deferred => true);
select better_supabase.audit('better_supabase.pick_waves', target_type => 'pick_wave', event_prefix => 'pick_wave', deferred => true);
select better_supabase.audit('better_supabase.pick_lines', target_type => 'pick_line', event_prefix => 'pick_line', deferred => true);
select better_supabase.audit('better_supabase.count_plans', target_type => 'count_plan', event_prefix => 'count_plan', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('warehouse', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: rfqs
-- @bsb-block-data rfqs
-- @bsb-hash sha256:7db726433f155e331334955c97aeedd219f47b8859c76f820b4923852ac240b1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.rfqs', target_type => 'rfq', event_prefix => 'rfq', deferred => true);
select better_supabase.audit('better_supabase.rfq_lines', target_type => 'rfq_line', event_prefix => 'rfq_line', deferred => true);
select better_supabase.audit('better_supabase.rfq_suppliers', target_type => 'rfq_supplier', event_prefix => 'rfq_supplier', deferred => true);
select better_supabase.audit('better_supabase.rfq_quotes', target_type => 'rfq_quote', event_prefix => 'rfq_quote', deferred => true);
select better_supabase.audit('better_supabase.rfq_quote_lines', target_type => 'rfq_quote_line', event_prefix => 'rfq_quote_line', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('rfqs', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: tills
-- @bsb-block-data tills
-- @bsb-hash sha256:5eddc235e69bc74f6e85f5e17ada478a7601a9e029516666989514d37c8fa306
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.tills', target_type => 'till', event_prefix => 'till', deferred => true);
select better_supabase.audit('better_supabase.till_sessions', target_type => 'till_session', event_prefix => 'till_session', deferred => true);
select better_supabase.audit('better_supabase.till_movements', target_type => 'till_movement', event_prefix => 'till_movement', deferred => true);
select better_supabase.audit('better_supabase.till_counts', target_type => 'till_count', event_prefix => 'till_count', deferred => true);
select better_supabase.audit('better_supabase.till_deposits', target_type => 'till_deposit', event_prefix => 'till_deposit', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('tills', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- better-supabase module: clinical-decision-support
-- @bsb-block-data clinical-decision-support
-- @bsb-hash sha256:b22e45a5983857209e568a7737b9863b52368538523049650700ee455b27302f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.care_alerts', target_type => 'care_alert', event_prefix => 'care_alert', deferred => true);
select better_supabase.audit('better_supabase.care_rules', target_type => 'care_rule', event_prefix => 'care_rule', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('clinical-decision-support', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
