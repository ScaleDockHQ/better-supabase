-- Three block tables take their convention names (ADR 0349), with the function
-- that shares one name. Renames only: no row moves.
do $$
begin
  if to_regclass('"better_supabase"."stream_kv"') is not null then
    alter table "better_supabase"."stream_kv" rename to "stream_entries";
    declare
      x record;
    begin
      for x in
        select 'constraint' as kind, k.conname::text as name from pg_catalog.pg_constraint k where k.conrelid = '"better_supabase"."stream_entries"'::regclass
        union all
        select 'index', i.relname::text from pg_catalog.pg_index ix join pg_catalog.pg_class i on i.oid = ix.indexrelid
          where ix.indrelid = '"better_supabase"."stream_entries"'::regclass and not exists (select 1 from pg_catalog.pg_constraint k where k.conindid = i.oid)
        union all
        select 'policy', p.polname::text from pg_catalog.pg_policy p where p.polrelid = '"better_supabase"."stream_entries"'::regclass
        order by 1 desc, 2
      loop
        if x.name ~ ('^(bsb_)?' || 'stream_kv' || '(_|$)') then
          execute case x.kind
            when 'constraint' then format('alter table %s rename constraint %I to %I', '"better_supabase"."stream_entries"', x.name, regexp_replace(x.name, '^(bsb_)?' || 'stream_kv', '\1' || 'stream_entries'))
            when 'index' then format('alter index %I.%I rename to %I', 'better_supabase', x.name, regexp_replace(x.name, '^(bsb_)?' || 'stream_kv', '\1' || 'stream_entries'))
            else format('alter policy %I on %s rename to %I', x.name, '"better_supabase"."stream_entries"', regexp_replace(x.name, '^(bsb_)?' || 'stream_kv', '\1' || 'stream_entries'))
          end;
        end if;
      end loop;
    end;
  end if;
  if to_regclass('"better_supabase"."invoice_e_endpoints"') is not null then
    alter table "better_supabase"."invoice_e_endpoints" rename to "e_invoice_endpoints";
    declare
      x record;
    begin
      for x in
        select 'constraint' as kind, k.conname::text as name from pg_catalog.pg_constraint k where k.conrelid = '"better_supabase"."e_invoice_endpoints"'::regclass
        union all
        select 'index', i.relname::text from pg_catalog.pg_index ix join pg_catalog.pg_class i on i.oid = ix.indexrelid
          where ix.indrelid = '"better_supabase"."e_invoice_endpoints"'::regclass and not exists (select 1 from pg_catalog.pg_constraint k where k.conindid = i.oid)
        union all
        select 'policy', p.polname::text from pg_catalog.pg_policy p where p.polrelid = '"better_supabase"."e_invoice_endpoints"'::regclass
        order by 1 desc, 2
      loop
        if x.name ~ ('^(bsb_)?' || 'invoice_e_endpoints' || '(_|$)') then
          execute case x.kind
            when 'constraint' then format('alter table %s rename constraint %I to %I', '"better_supabase"."e_invoice_endpoints"', x.name, regexp_replace(x.name, '^(bsb_)?' || 'invoice_e_endpoints', '\1' || 'e_invoice_endpoints'))
            when 'index' then format('alter index %I.%I rename to %I', 'better_supabase', x.name, regexp_replace(x.name, '^(bsb_)?' || 'invoice_e_endpoints', '\1' || 'e_invoice_endpoints'))
            else format('alter policy %I on %s rename to %I', x.name, '"better_supabase"."e_invoice_endpoints"', regexp_replace(x.name, '^(bsb_)?' || 'invoice_e_endpoints', '\1' || 'e_invoice_endpoints'))
          end;
        end if;
      end loop;
    end;
  end if;
  if to_regclass('"better_supabase"."workflow_step_library"') is not null then
    alter table "better_supabase"."workflow_step_library" rename to "workflow_step_templates";
    declare
      x record;
    begin
      for x in
        select 'constraint' as kind, k.conname::text as name from pg_catalog.pg_constraint k where k.conrelid = '"better_supabase"."workflow_step_templates"'::regclass
        union all
        select 'index', i.relname::text from pg_catalog.pg_index ix join pg_catalog.pg_class i on i.oid = ix.indexrelid
          where ix.indrelid = '"better_supabase"."workflow_step_templates"'::regclass and not exists (select 1 from pg_catalog.pg_constraint k where k.conindid = i.oid)
        union all
        select 'policy', p.polname::text from pg_catalog.pg_policy p where p.polrelid = '"better_supabase"."workflow_step_templates"'::regclass
        order by 1 desc, 2
      loop
        if x.name ~ ('^(bsb_)?' || 'workflow_step_library' || '(_|$)') then
          execute case x.kind
            when 'constraint' then format('alter table %s rename constraint %I to %I', '"better_supabase"."workflow_step_templates"', x.name, regexp_replace(x.name, '^(bsb_)?' || 'workflow_step_library', '\1' || 'workflow_step_templates'))
            when 'index' then format('alter index %I.%I rename to %I', 'better_supabase', x.name, regexp_replace(x.name, '^(bsb_)?' || 'workflow_step_library', '\1' || 'workflow_step_templates'))
            else format('alter policy %I on %s rename to %I', x.name, '"better_supabase"."workflow_step_templates"', regexp_replace(x.name, '^(bsb_)?' || 'workflow_step_library', '\1' || 'workflow_step_templates'))
          end;
        end if;
      end loop;
    end;
  end if;
  if to_regprocedure('better_supabase.invoice_e_endpoints(uuid)') is not null then
    alter function better_supabase.invoice_e_endpoints(uuid) rename to e_invoice_endpoints;
  end if;
end
$$;
