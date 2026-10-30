-- better-supabase module: permissions
-- @bsb-block-data permissions
-- @bsb-hash sha256:9764b09aece35ae78ffbebe45c5c143b8212edb1394eaea0012d5c632a2f5614
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
    ('controls.*', array['compliance.*']::text[], true),
    ('controls.acknowledge', array['compliance.acknowledge']::text[], true),
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
