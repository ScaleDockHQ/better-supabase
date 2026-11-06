-- better-supabase module: compliance
-- @bsb-block-data compliance
-- @bsb-hash sha256:37dc0cb211a7ecf3ba367d407b46c25f9289eb7757a851e305f76b67c60ed13e
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
values ('compliance', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
