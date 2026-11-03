-- better-supabase upgrade: steps that run before the schema diff.

-- activities: version 3 to 4. Activity notes' action_items are copied into tasks through create_task and the column is dropped. Without the tasks block the items are only dropped when the column is empty.
-- Activity note action items are tasks now: copy what is left and drop the column.
do $upgrade$
begin
  if to_regclass('"better_supabase"."engagement_notes"') is not null and exists (select 1 from pg_attribute where attrelid = to_regclass('"better_supabase"."engagement_notes"') and attname = 'action_items' and not attisdropped) then
    if exists (select 1 from "better_supabase"."engagement_notes" x where jsonb_typeof(x.action_items) = 'array' and jsonb_array_length(x.action_items) > 0) then
      if to_regclass('"better_supabase"."work_items"') is null then
        raise exception 'activity notes still hold action items and the tasks table is not installed yet: run upgrade again once the tasks block is applied, or clear the column';
      end if;
      create table if not exists "better_supabase"."activity_note_actions" (
        "id" uuid primary key default gen_random_uuid(),
        "tenant_id" uuid not null,
        "activity_id" uuid not null references "better_supabase"."activities" ("id") on delete cascade,
        "task_id" uuid not null references "better_supabase"."work_items" ("id") on delete cascade,
        "created_at" timestamptz not null default now(),
        unique ("activity_id", "task_id")
      );
      execute 'do $$
declare
  v_note record;
  v_item jsonb;
  v_title text;
  v_owner uuid;
  v_due timestamptz;
  v_task uuid;
  v_position integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> ''role'', ''''), session_user::text) in (''service_role'', ''postgres'', ''supabase_admin'')) then
    raise exception ''the activities upgrade copies action_items into tasks as the service role or the migration role'';
  end if;
  for v_note in
    select x."activity_id" as id, x."tenant_id" as tenant, x.action_items as items
    from "better_supabase"."engagement_notes" x
    where jsonb_typeof(x.action_items) = ''array''
      and jsonb_array_length(x.action_items) > 0
      and not exists (select 1 from "better_supabase"."activity_note_actions" y where y."activity_id" = x."activity_id")
    order by x."activity_id"
  loop
    v_position := 0;
    for v_item in select e.value from jsonb_array_elements(v_note.items) e loop
      v_position := v_position + 1;
      v_title := left(nullif(btrim(coalesce(v_item ->> ''text'', v_item ->> ''title'', '''')), ''''), 500);
      if v_title is null then
        v_title := ''Action item '' || v_position;
      end if;
      v_owner := null;
      v_due := null;
      begin
        v_owner := (v_item ->> ''ownerId'')::uuid;
      exception when others then
        v_owner := null;
      end;
      begin
        v_due := (v_item ->> ''dueAt'')::timestamptz;
      exception when others then
        v_due := null;
      end;
      v_task := ("better_supabase"."create_work_item"(
        v_note.tenant,
        jsonb_strip_nulls(jsonb_build_object(''title'', v_title, ''dueAt'', v_due)),
        case when v_owner is null then ''{}''::uuid[] else array[v_owner] end
      ) ->> ''id'')::uuid;
      insert into "better_supabase"."activity_note_actions" ("tenant_id", "activity_id", "task_id")
      values (v_note.tenant, v_note.id, v_task);
    end loop;
  end loop;
end;
$$;';
    end if;
    alter table "better_supabase"."engagement_notes" drop column action_items;
  end if;
end;
$upgrade$;

-- invoices: version 2 to 3. The delivery log is e_invoice_deliveries (ADR 0206).
do $$ begin if to_regclass('"better_supabase"."invoice_e_deliveries"') is not null and to_regclass('"better_supabase"."e_invoice_deliveries"') is null then alter table "better_supabase"."invoice_e_deliveries" rename to "e_invoice_deliveries"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."e_invoice_deliveries"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."e_invoice_deliveries"'::regclass loop
    if left(o.name, 21) = 'invoice_e_deliveries_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'e_invoice_deliveries' || substr(o.name, 21)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'e_invoice_deliveries' || substr(o.name, 21));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."e_invoice_deliveries"'::regclass loop
    if left(o.name, 21) = 'invoice_e_deliveries_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."e_invoice_deliveries"'::regclass and x.polname = 'e_invoice_deliveries' || substr(o.name, 21)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."e_invoice_deliveries"', 'e_invoice_deliveries' || substr(o.name, 21));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."e_invoice_deliveries"'::regclass and not t.tgisinternal loop
    if left(o.name, 21) = 'invoice_e_deliveries_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."e_invoice_deliveries"'::regclass and x.tgname = 'e_invoice_deliveries' || substr(o.name, 21)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."e_invoice_deliveries"', 'e_invoice_deliveries' || substr(o.name, 21));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."e_invoice_deliveries"'::regclass loop
    if left(o.name, 21) = 'invoice_e_deliveries_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'e_invoice_deliveries' || substr(o.name, 21)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."e_invoice_deliveries"', o.name, 'e_invoice_deliveries' || substr(o.name, 21));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."e_invoice_deliveries"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 21) = 'invoice_e_deliveries_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'e_invoice_deliveries' || substr(o.name, 21)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'e_invoice_deliveries' || substr(o.name, 21));
    end if;
  end loop;
end $$;
