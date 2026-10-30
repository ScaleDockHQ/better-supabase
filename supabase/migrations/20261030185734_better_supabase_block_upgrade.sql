-- better-supabase upgrade: steps that run before the schema diff.

-- sso: version 1 to 2. The organization_domains table is sso_domains (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."organization_domains"') is not null and to_regclass('"better_supabase"."sso_domains"') is null then alter table "better_supabase"."organization_domains" rename to "sso_domains"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."sso_domains"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."sso_domains"'::regclass loop
    if left(o.name, 21) = 'organization_domains_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'sso_domains' || substr(o.name, 21)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'sso_domains' || substr(o.name, 21));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."sso_domains"'::regclass loop
    if left(o.name, 21) = 'organization_domains_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."sso_domains"'::regclass and x.polname = 'sso_domains' || substr(o.name, 21)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."sso_domains"', 'sso_domains' || substr(o.name, 21));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."sso_domains"'::regclass and not t.tgisinternal loop
    if left(o.name, 21) = 'organization_domains_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."sso_domains"'::regclass and x.tgname = 'sso_domains' || substr(o.name, 21)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."sso_domains"', 'sso_domains' || substr(o.name, 21));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."sso_domains"'::regclass loop
    if left(o.name, 21) = 'organization_domains_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'sso_domains' || substr(o.name, 21)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."sso_domains"', o.name, 'sso_domains' || substr(o.name, 21));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."sso_domains"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 21) = 'organization_domains_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'sso_domains' || substr(o.name, 21)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'sso_domains' || substr(o.name, 21));
    end if;
  end loop;
end $$;

-- sso: version 1 to 2. The organization_sso_providers table is sso_providers (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."organization_sso_providers"') is not null and to_regclass('"better_supabase"."sso_providers"') is null then alter table "better_supabase"."organization_sso_providers" rename to "sso_providers"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."sso_providers"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."sso_providers"'::regclass loop
    if left(o.name, 27) = 'organization_sso_providers_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'sso_providers' || substr(o.name, 27)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'sso_providers' || substr(o.name, 27));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."sso_providers"'::regclass loop
    if left(o.name, 27) = 'organization_sso_providers_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."sso_providers"'::regclass and x.polname = 'sso_providers' || substr(o.name, 27)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."sso_providers"', 'sso_providers' || substr(o.name, 27));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."sso_providers"'::regclass and not t.tgisinternal loop
    if left(o.name, 27) = 'organization_sso_providers_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."sso_providers"'::regclass and x.tgname = 'sso_providers' || substr(o.name, 27)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."sso_providers"', 'sso_providers' || substr(o.name, 27));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."sso_providers"'::regclass loop
    if left(o.name, 27) = 'organization_sso_providers_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'sso_providers' || substr(o.name, 27)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."sso_providers"', o.name, 'sso_providers' || substr(o.name, 27));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."sso_providers"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 27) = 'organization_sso_providers_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'sso_providers' || substr(o.name, 27)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'sso_providers' || substr(o.name, 27));
    end if;
  end loop;
end $$;

-- inbox: version 6 to 7. The message_deliveries table is inbox_message_deliveries (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."message_deliveries"') is not null and to_regclass('"better_supabase"."inbox_message_deliveries"') is null then alter table "better_supabase"."message_deliveries" rename to "inbox_message_deliveries"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."inbox_message_deliveries"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."inbox_message_deliveries"'::regclass loop
    if left(o.name, 19) = 'message_deliveries_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'inbox_message_deliveries' || substr(o.name, 19)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'inbox_message_deliveries' || substr(o.name, 19));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."inbox_message_deliveries"'::regclass loop
    if left(o.name, 19) = 'message_deliveries_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."inbox_message_deliveries"'::regclass and x.polname = 'inbox_message_deliveries' || substr(o.name, 19)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."inbox_message_deliveries"', 'inbox_message_deliveries' || substr(o.name, 19));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."inbox_message_deliveries"'::regclass and not t.tgisinternal loop
    if left(o.name, 19) = 'message_deliveries_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."inbox_message_deliveries"'::regclass and x.tgname = 'inbox_message_deliveries' || substr(o.name, 19)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."inbox_message_deliveries"', 'inbox_message_deliveries' || substr(o.name, 19));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."inbox_message_deliveries"'::regclass loop
    if left(o.name, 19) = 'message_deliveries_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'inbox_message_deliveries' || substr(o.name, 19)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."inbox_message_deliveries"', o.name, 'inbox_message_deliveries' || substr(o.name, 19));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."inbox_message_deliveries"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 19) = 'message_deliveries_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'inbox_message_deliveries' || substr(o.name, 19)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'inbox_message_deliveries' || substr(o.name, 19));
    end if;
  end loop;
end $$;

-- inbox: version 6 to 7. The conversation_events table is inbox_conversation_events (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."conversation_events"') is not null and to_regclass('"better_supabase"."inbox_conversation_events"') is null then alter table "better_supabase"."conversation_events" rename to "inbox_conversation_events"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."inbox_conversation_events"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."inbox_conversation_events"'::regclass loop
    if left(o.name, 20) = 'conversation_events_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'inbox_conversation_events' || substr(o.name, 20)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'inbox_conversation_events' || substr(o.name, 20));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."inbox_conversation_events"'::regclass loop
    if left(o.name, 20) = 'conversation_events_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."inbox_conversation_events"'::regclass and x.polname = 'inbox_conversation_events' || substr(o.name, 20)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."inbox_conversation_events"', 'inbox_conversation_events' || substr(o.name, 20));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."inbox_conversation_events"'::regclass and not t.tgisinternal loop
    if left(o.name, 20) = 'conversation_events_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."inbox_conversation_events"'::regclass and x.tgname = 'inbox_conversation_events' || substr(o.name, 20)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."inbox_conversation_events"', 'inbox_conversation_events' || substr(o.name, 20));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."inbox_conversation_events"'::regclass loop
    if left(o.name, 20) = 'conversation_events_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'inbox_conversation_events' || substr(o.name, 20)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."inbox_conversation_events"', o.name, 'inbox_conversation_events' || substr(o.name, 20));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."inbox_conversation_events"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 20) = 'conversation_events_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'inbox_conversation_events' || substr(o.name, 20)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'inbox_conversation_events' || substr(o.name, 20));
    end if;
  end loop;
end $$;

-- inbox: version 6 to 7. The inbound_events table is inbox_inbound_events (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."inbound_events"') is not null and to_regclass('"better_supabase"."inbox_inbound_events"') is null then alter table "better_supabase"."inbound_events" rename to "inbox_inbound_events"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."inbox_inbound_events"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."inbox_inbound_events"'::regclass loop
    if left(o.name, 15) = 'inbound_events_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'inbox_inbound_events' || substr(o.name, 15)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'inbox_inbound_events' || substr(o.name, 15));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."inbox_inbound_events"'::regclass loop
    if left(o.name, 15) = 'inbound_events_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."inbox_inbound_events"'::regclass and x.polname = 'inbox_inbound_events' || substr(o.name, 15)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."inbox_inbound_events"', 'inbox_inbound_events' || substr(o.name, 15));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."inbox_inbound_events"'::regclass and not t.tgisinternal loop
    if left(o.name, 15) = 'inbound_events_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."inbox_inbound_events"'::regclass and x.tgname = 'inbox_inbound_events' || substr(o.name, 15)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."inbox_inbound_events"', 'inbox_inbound_events' || substr(o.name, 15));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."inbox_inbound_events"'::regclass loop
    if left(o.name, 15) = 'inbound_events_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'inbox_inbound_events' || substr(o.name, 15)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."inbox_inbound_events"', o.name, 'inbox_inbound_events' || substr(o.name, 15));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."inbox_inbound_events"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 15) = 'inbound_events_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'inbox_inbound_events' || substr(o.name, 15)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'inbox_inbound_events' || substr(o.name, 15));
    end if;
  end loop;
end $$;

-- inbox: version 6 to 7. The message_templates table is inbox_message_templates (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."message_templates"') is not null and to_regclass('"better_supabase"."inbox_message_templates"') is null then alter table "better_supabase"."message_templates" rename to "inbox_message_templates"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."inbox_message_templates"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."inbox_message_templates"'::regclass loop
    if left(o.name, 18) = 'message_templates_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'inbox_message_templates' || substr(o.name, 18)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'inbox_message_templates' || substr(o.name, 18));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."inbox_message_templates"'::regclass loop
    if left(o.name, 18) = 'message_templates_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."inbox_message_templates"'::regclass and x.polname = 'inbox_message_templates' || substr(o.name, 18)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."inbox_message_templates"', 'inbox_message_templates' || substr(o.name, 18));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."inbox_message_templates"'::regclass and not t.tgisinternal loop
    if left(o.name, 18) = 'message_templates_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."inbox_message_templates"'::regclass and x.tgname = 'inbox_message_templates' || substr(o.name, 18)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."inbox_message_templates"', 'inbox_message_templates' || substr(o.name, 18));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."inbox_message_templates"'::regclass loop
    if left(o.name, 18) = 'message_templates_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'inbox_message_templates' || substr(o.name, 18)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."inbox_message_templates"', o.name, 'inbox_message_templates' || substr(o.name, 18));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."inbox_message_templates"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 18) = 'message_templates_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'inbox_message_templates' || substr(o.name, 18)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'inbox_message_templates' || substr(o.name, 18));
    end if;
  end loop;
end $$;

-- memory: version 4 to 5. The ai_message_embeddings table is memory_message_embeddings (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."ai_message_embeddings"') is not null and to_regclass('"better_supabase"."memory_message_embeddings"') is null then alter table "better_supabase"."ai_message_embeddings" rename to "memory_message_embeddings"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."memory_message_embeddings"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."memory_message_embeddings"'::regclass loop
    if left(o.name, 22) = 'ai_message_embeddings_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'memory_message_embeddings' || substr(o.name, 22)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'memory_message_embeddings' || substr(o.name, 22));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."memory_message_embeddings"'::regclass loop
    if left(o.name, 22) = 'ai_message_embeddings_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."memory_message_embeddings"'::regclass and x.polname = 'memory_message_embeddings' || substr(o.name, 22)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."memory_message_embeddings"', 'memory_message_embeddings' || substr(o.name, 22));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."memory_message_embeddings"'::regclass and not t.tgisinternal loop
    if left(o.name, 22) = 'ai_message_embeddings_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."memory_message_embeddings"'::regclass and x.tgname = 'memory_message_embeddings' || substr(o.name, 22)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."memory_message_embeddings"', 'memory_message_embeddings' || substr(o.name, 22));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."memory_message_embeddings"'::regclass loop
    if left(o.name, 22) = 'ai_message_embeddings_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'memory_message_embeddings' || substr(o.name, 22)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."memory_message_embeddings"', o.name, 'memory_message_embeddings' || substr(o.name, 22));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."memory_message_embeddings"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 22) = 'ai_message_embeddings_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'memory_message_embeddings' || substr(o.name, 22)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'memory_message_embeddings' || substr(o.name, 22));
    end if;
  end loop;
end $$;

-- catalog: version 3 to 4. The categories table is catalog_categories (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."categories"') is not null and to_regclass('"better_supabase"."catalog_categories"') is null then alter table "better_supabase"."categories" rename to "catalog_categories"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."catalog_categories"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."catalog_categories"'::regclass loop
    if left(o.name, 11) = 'categories_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'catalog_categories' || substr(o.name, 11)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'catalog_categories' || substr(o.name, 11));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."catalog_categories"'::regclass loop
    if left(o.name, 11) = 'categories_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."catalog_categories"'::regclass and x.polname = 'catalog_categories' || substr(o.name, 11)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."catalog_categories"', 'catalog_categories' || substr(o.name, 11));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."catalog_categories"'::regclass and not t.tgisinternal loop
    if left(o.name, 11) = 'categories_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."catalog_categories"'::regclass and x.tgname = 'catalog_categories' || substr(o.name, 11)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."catalog_categories"', 'catalog_categories' || substr(o.name, 11));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."catalog_categories"'::regclass loop
    if left(o.name, 11) = 'categories_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'catalog_categories' || substr(o.name, 11)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."catalog_categories"', o.name, 'catalog_categories' || substr(o.name, 11));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."catalog_categories"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 11) = 'categories_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'catalog_categories' || substr(o.name, 11)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'catalog_categories' || substr(o.name, 11));
    end if;
  end loop;
end $$;

-- catalog: version 3 to 4. The price_lists table is catalog_price_lists (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."price_lists"') is not null and to_regclass('"better_supabase"."catalog_price_lists"') is null then alter table "better_supabase"."price_lists" rename to "catalog_price_lists"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."catalog_price_lists"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."catalog_price_lists"'::regclass loop
    if left(o.name, 12) = 'price_lists_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'catalog_price_lists' || substr(o.name, 12)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'catalog_price_lists' || substr(o.name, 12));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."catalog_price_lists"'::regclass loop
    if left(o.name, 12) = 'price_lists_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."catalog_price_lists"'::regclass and x.polname = 'catalog_price_lists' || substr(o.name, 12)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."catalog_price_lists"', 'catalog_price_lists' || substr(o.name, 12));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."catalog_price_lists"'::regclass and not t.tgisinternal loop
    if left(o.name, 12) = 'price_lists_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."catalog_price_lists"'::regclass and x.tgname = 'catalog_price_lists' || substr(o.name, 12)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."catalog_price_lists"', 'catalog_price_lists' || substr(o.name, 12));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."catalog_price_lists"'::regclass loop
    if left(o.name, 12) = 'price_lists_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'catalog_price_lists' || substr(o.name, 12)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."catalog_price_lists"', o.name, 'catalog_price_lists' || substr(o.name, 12));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."catalog_price_lists"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 12) = 'price_lists_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'catalog_price_lists' || substr(o.name, 12)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'catalog_price_lists' || substr(o.name, 12));
    end if;
  end loop;
end $$;

-- catalog: version 3 to 4. The storefronts table is catalog_storefronts (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."storefronts"') is not null and to_regclass('"better_supabase"."catalog_storefronts"') is null then alter table "better_supabase"."storefronts" rename to "catalog_storefronts"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."catalog_storefronts"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."catalog_storefronts"'::regclass loop
    if left(o.name, 12) = 'storefronts_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'catalog_storefronts' || substr(o.name, 12)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'catalog_storefronts' || substr(o.name, 12));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."catalog_storefronts"'::regclass loop
    if left(o.name, 12) = 'storefronts_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."catalog_storefronts"'::regclass and x.polname = 'catalog_storefronts' || substr(o.name, 12)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."catalog_storefronts"', 'catalog_storefronts' || substr(o.name, 12));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."catalog_storefronts"'::regclass and not t.tgisinternal loop
    if left(o.name, 12) = 'storefronts_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."catalog_storefronts"'::regclass and x.tgname = 'catalog_storefronts' || substr(o.name, 12)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."catalog_storefronts"', 'catalog_storefronts' || substr(o.name, 12));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."catalog_storefronts"'::regclass loop
    if left(o.name, 12) = 'storefronts_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'catalog_storefronts' || substr(o.name, 12)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."catalog_storefronts"', o.name, 'catalog_storefronts' || substr(o.name, 12));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."catalog_storefronts"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 12) = 'storefronts_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'catalog_storefronts' || substr(o.name, 12)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'catalog_storefronts' || substr(o.name, 12));
    end if;
  end loop;
end $$;

-- orders: version 3 to 4. The fulfillment_lines table is order_fulfillment_lines (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."fulfillment_lines"') is not null and to_regclass('"better_supabase"."order_fulfillment_lines"') is null then alter table "better_supabase"."fulfillment_lines" rename to "order_fulfillment_lines"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."order_fulfillment_lines"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."order_fulfillment_lines"'::regclass loop
    if left(o.name, 18) = 'fulfillment_lines_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'order_fulfillment_lines' || substr(o.name, 18)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'order_fulfillment_lines' || substr(o.name, 18));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."order_fulfillment_lines"'::regclass loop
    if left(o.name, 18) = 'fulfillment_lines_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."order_fulfillment_lines"'::regclass and x.polname = 'order_fulfillment_lines' || substr(o.name, 18)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."order_fulfillment_lines"', 'order_fulfillment_lines' || substr(o.name, 18));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."order_fulfillment_lines"'::regclass and not t.tgisinternal loop
    if left(o.name, 18) = 'fulfillment_lines_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."order_fulfillment_lines"'::regclass and x.tgname = 'order_fulfillment_lines' || substr(o.name, 18)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."order_fulfillment_lines"', 'order_fulfillment_lines' || substr(o.name, 18));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."order_fulfillment_lines"'::regclass loop
    if left(o.name, 18) = 'fulfillment_lines_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'order_fulfillment_lines' || substr(o.name, 18)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."order_fulfillment_lines"', o.name, 'order_fulfillment_lines' || substr(o.name, 18));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."order_fulfillment_lines"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 18) = 'fulfillment_lines_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'order_fulfillment_lines' || substr(o.name, 18)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'order_fulfillment_lines' || substr(o.name, 18));
    end if;
  end loop;
end $$;

-- orders: version 3 to 4. The fulfillments table is order_fulfillments (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."fulfillments"') is not null and to_regclass('"better_supabase"."order_fulfillments"') is null then alter table "better_supabase"."fulfillments" rename to "order_fulfillments"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."order_fulfillments"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."order_fulfillments"'::regclass loop
    if left(o.name, 13) = 'fulfillments_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'order_fulfillments' || substr(o.name, 13)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'order_fulfillments' || substr(o.name, 13));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."order_fulfillments"'::regclass loop
    if left(o.name, 13) = 'fulfillments_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."order_fulfillments"'::regclass and x.polname = 'order_fulfillments' || substr(o.name, 13)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."order_fulfillments"', 'order_fulfillments' || substr(o.name, 13));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."order_fulfillments"'::regclass and not t.tgisinternal loop
    if left(o.name, 13) = 'fulfillments_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."order_fulfillments"'::regclass and x.tgname = 'order_fulfillments' || substr(o.name, 13)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."order_fulfillments"', 'order_fulfillments' || substr(o.name, 13));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."order_fulfillments"'::regclass loop
    if left(o.name, 13) = 'fulfillments_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'order_fulfillments' || substr(o.name, 13)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."order_fulfillments"', o.name, 'order_fulfillments' || substr(o.name, 13));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."order_fulfillments"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 13) = 'fulfillments_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'order_fulfillments' || substr(o.name, 13)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'order_fulfillments' || substr(o.name, 13));
    end if;
  end loop;
end $$;

-- orders: version 3 to 4. The kitchen_routes table is order_kitchen_routes (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."kitchen_routes"') is not null and to_regclass('"better_supabase"."order_kitchen_routes"') is null then alter table "better_supabase"."kitchen_routes" rename to "order_kitchen_routes"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."order_kitchen_routes"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."order_kitchen_routes"'::regclass loop
    if left(o.name, 15) = 'kitchen_routes_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'order_kitchen_routes' || substr(o.name, 15)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'order_kitchen_routes' || substr(o.name, 15));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."order_kitchen_routes"'::regclass loop
    if left(o.name, 15) = 'kitchen_routes_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."order_kitchen_routes"'::regclass and x.polname = 'order_kitchen_routes' || substr(o.name, 15)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."order_kitchen_routes"', 'order_kitchen_routes' || substr(o.name, 15));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."order_kitchen_routes"'::regclass and not t.tgisinternal loop
    if left(o.name, 15) = 'kitchen_routes_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."order_kitchen_routes"'::regclass and x.tgname = 'order_kitchen_routes' || substr(o.name, 15)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."order_kitchen_routes"', 'order_kitchen_routes' || substr(o.name, 15));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."order_kitchen_routes"'::regclass loop
    if left(o.name, 15) = 'kitchen_routes_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'order_kitchen_routes' || substr(o.name, 15)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."order_kitchen_routes"', o.name, 'order_kitchen_routes' || substr(o.name, 15));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."order_kitchen_routes"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 15) = 'kitchen_routes_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'order_kitchen_routes' || substr(o.name, 15)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'order_kitchen_routes' || substr(o.name, 15));
    end if;
  end loop;
end $$;

-- orders: version 3 to 4. The kitchen_stations table is order_kitchen_stations (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."kitchen_stations"') is not null and to_regclass('"better_supabase"."order_kitchen_stations"') is null then alter table "better_supabase"."kitchen_stations" rename to "order_kitchen_stations"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."order_kitchen_stations"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."order_kitchen_stations"'::regclass loop
    if left(o.name, 17) = 'kitchen_stations_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'order_kitchen_stations' || substr(o.name, 17)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'order_kitchen_stations' || substr(o.name, 17));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."order_kitchen_stations"'::regclass loop
    if left(o.name, 17) = 'kitchen_stations_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."order_kitchen_stations"'::regclass and x.polname = 'order_kitchen_stations' || substr(o.name, 17)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."order_kitchen_stations"', 'order_kitchen_stations' || substr(o.name, 17));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."order_kitchen_stations"'::regclass and not t.tgisinternal loop
    if left(o.name, 17) = 'kitchen_stations_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."order_kitchen_stations"'::regclass and x.tgname = 'order_kitchen_stations' || substr(o.name, 17)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."order_kitchen_stations"', 'order_kitchen_stations' || substr(o.name, 17));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."order_kitchen_stations"'::regclass loop
    if left(o.name, 17) = 'kitchen_stations_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'order_kitchen_stations' || substr(o.name, 17)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."order_kitchen_stations"', o.name, 'order_kitchen_stations' || substr(o.name, 17));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."order_kitchen_stations"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 17) = 'kitchen_stations_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'order_kitchen_stations' || substr(o.name, 17)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'order_kitchen_stations' || substr(o.name, 17));
    end if;
  end loop;
end $$;

-- orders: version 3 to 4. The shipping_rates table is order_shipping_rates (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."shipping_rates"') is not null and to_regclass('"better_supabase"."order_shipping_rates"') is null then alter table "better_supabase"."shipping_rates" rename to "order_shipping_rates"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."order_shipping_rates"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."order_shipping_rates"'::regclass loop
    if left(o.name, 15) = 'shipping_rates_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'order_shipping_rates' || substr(o.name, 15)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'order_shipping_rates' || substr(o.name, 15));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."order_shipping_rates"'::regclass loop
    if left(o.name, 15) = 'shipping_rates_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."order_shipping_rates"'::regclass and x.polname = 'order_shipping_rates' || substr(o.name, 15)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."order_shipping_rates"', 'order_shipping_rates' || substr(o.name, 15));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."order_shipping_rates"'::regclass and not t.tgisinternal loop
    if left(o.name, 15) = 'shipping_rates_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."order_shipping_rates"'::regclass and x.tgname = 'order_shipping_rates' || substr(o.name, 15)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."order_shipping_rates"', 'order_shipping_rates' || substr(o.name, 15));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."order_shipping_rates"'::regclass loop
    if left(o.name, 15) = 'shipping_rates_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'order_shipping_rates' || substr(o.name, 15)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."order_shipping_rates"', o.name, 'order_shipping_rates' || substr(o.name, 15));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."order_shipping_rates"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 15) = 'shipping_rates_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'order_shipping_rates' || substr(o.name, 15)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'order_shipping_rates' || substr(o.name, 15));
    end if;
  end loop;
end $$;

-- activities: version 1 to 2. The engagements table is activities (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."engagements"') is not null and to_regclass('"better_supabase"."activities"') is null then alter table "better_supabase"."engagements" rename to "activities"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."activities"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."activities"'::regclass loop
    if left(o.name, 12) = 'engagements_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'activities' || substr(o.name, 12)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'activities' || substr(o.name, 12));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."activities"'::regclass loop
    if left(o.name, 12) = 'engagements_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."activities"'::regclass and x.polname = 'activities' || substr(o.name, 12)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."activities"', 'activities' || substr(o.name, 12));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."activities"'::regclass and not t.tgisinternal loop
    if left(o.name, 12) = 'engagements_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."activities"'::regclass and x.tgname = 'activities' || substr(o.name, 12)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."activities"', 'activities' || substr(o.name, 12));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."activities"'::regclass loop
    if left(o.name, 12) = 'engagements_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'activities' || substr(o.name, 12)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."activities"', o.name, 'activities' || substr(o.name, 12));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."activities"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 12) = 'engagements_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'activities' || substr(o.name, 12)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'activities' || substr(o.name, 12));
    end if;
  end loop;
end $$;

-- goals: version 1 to 2. The targets table is goals (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."targets"') is not null and to_regclass('"better_supabase"."goals"') is null then alter table "better_supabase"."targets" rename to "goals"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."goals"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."goals"'::regclass loop
    if left(o.name, 8) = 'targets_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'goals' || substr(o.name, 8)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'goals' || substr(o.name, 8));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."goals"'::regclass loop
    if left(o.name, 8) = 'targets_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."goals"'::regclass and x.polname = 'goals' || substr(o.name, 8)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."goals"', 'goals' || substr(o.name, 8));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."goals"'::regclass and not t.tgisinternal loop
    if left(o.name, 8) = 'targets_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."goals"'::regclass and x.tgname = 'goals' || substr(o.name, 8)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."goals"', 'goals' || substr(o.name, 8));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."goals"'::regclass loop
    if left(o.name, 8) = 'targets_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'goals' || substr(o.name, 8)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."goals"', o.name, 'goals' || substr(o.name, 8));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."goals"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 8) = 'targets_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'goals' || substr(o.name, 8)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'goals' || substr(o.name, 8));
    end if;
  end loop;
end $$;

-- automations: version 1 to 2. The rule_defaults table is automation_defaults (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."rule_defaults"') is not null and to_regclass('"better_supabase"."automation_defaults"') is null then alter table "better_supabase"."rule_defaults" rename to "automation_defaults"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."automation_defaults"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."automation_defaults"'::regclass loop
    if left(o.name, 14) = 'rule_defaults_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'automation_defaults' || substr(o.name, 14)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'automation_defaults' || substr(o.name, 14));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."automation_defaults"'::regclass loop
    if left(o.name, 14) = 'rule_defaults_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."automation_defaults"'::regclass and x.polname = 'automation_defaults' || substr(o.name, 14)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."automation_defaults"', 'automation_defaults' || substr(o.name, 14));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."automation_defaults"'::regclass and not t.tgisinternal loop
    if left(o.name, 14) = 'rule_defaults_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."automation_defaults"'::regclass and x.tgname = 'automation_defaults' || substr(o.name, 14)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."automation_defaults"', 'automation_defaults' || substr(o.name, 14));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."automation_defaults"'::regclass loop
    if left(o.name, 14) = 'rule_defaults_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'automation_defaults' || substr(o.name, 14)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."automation_defaults"', o.name, 'automation_defaults' || substr(o.name, 14));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."automation_defaults"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 14) = 'rule_defaults_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'automation_defaults' || substr(o.name, 14)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'automation_defaults' || substr(o.name, 14));
    end if;
  end loop;
end $$;

-- automations: version 1 to 2. The rule_evaluations table is automation_evaluations (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."rule_evaluations"') is not null and to_regclass('"better_supabase"."automation_evaluations"') is null then alter table "better_supabase"."rule_evaluations" rename to "automation_evaluations"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."automation_evaluations"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."automation_evaluations"'::regclass loop
    if left(o.name, 17) = 'rule_evaluations_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'automation_evaluations' || substr(o.name, 17)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'automation_evaluations' || substr(o.name, 17));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."automation_evaluations"'::regclass loop
    if left(o.name, 17) = 'rule_evaluations_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."automation_evaluations"'::regclass and x.polname = 'automation_evaluations' || substr(o.name, 17)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."automation_evaluations"', 'automation_evaluations' || substr(o.name, 17));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."automation_evaluations"'::regclass and not t.tgisinternal loop
    if left(o.name, 17) = 'rule_evaluations_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."automation_evaluations"'::regclass and x.tgname = 'automation_evaluations' || substr(o.name, 17)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."automation_evaluations"', 'automation_evaluations' || substr(o.name, 17));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."automation_evaluations"'::regclass loop
    if left(o.name, 17) = 'rule_evaluations_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'automation_evaluations' || substr(o.name, 17)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."automation_evaluations"', o.name, 'automation_evaluations' || substr(o.name, 17));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."automation_evaluations"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 17) = 'rule_evaluations_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'automation_evaluations' || substr(o.name, 17)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'automation_evaluations' || substr(o.name, 17));
    end if;
  end loop;
end $$;

-- automations: version 1 to 2. The rule_fields table is automation_fields (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."rule_fields"') is not null and to_regclass('"better_supabase"."automation_fields"') is null then alter table "better_supabase"."rule_fields" rename to "automation_fields"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."automation_fields"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."automation_fields"'::regclass loop
    if left(o.name, 12) = 'rule_fields_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'automation_fields' || substr(o.name, 12)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'automation_fields' || substr(o.name, 12));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."automation_fields"'::regclass loop
    if left(o.name, 12) = 'rule_fields_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."automation_fields"'::regclass and x.polname = 'automation_fields' || substr(o.name, 12)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."automation_fields"', 'automation_fields' || substr(o.name, 12));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."automation_fields"'::regclass and not t.tgisinternal loop
    if left(o.name, 12) = 'rule_fields_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."automation_fields"'::regclass and x.tgname = 'automation_fields' || substr(o.name, 12)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."automation_fields"', 'automation_fields' || substr(o.name, 12));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."automation_fields"'::regclass loop
    if left(o.name, 12) = 'rule_fields_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'automation_fields' || substr(o.name, 12)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."automation_fields"', o.name, 'automation_fields' || substr(o.name, 12));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."automation_fields"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 12) = 'rule_fields_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'automation_fields' || substr(o.name, 12)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'automation_fields' || substr(o.name, 12));
    end if;
  end loop;
end $$;

-- automations: version 1 to 2. The rules table is automations (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."rules"') is not null and to_regclass('"better_supabase"."automations"') is null then alter table "better_supabase"."rules" rename to "automations"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."automations"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."automations"'::regclass loop
    if left(o.name, 6) = 'rules_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'automations' || substr(o.name, 6)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'automations' || substr(o.name, 6));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."automations"'::regclass loop
    if left(o.name, 6) = 'rules_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."automations"'::regclass and x.polname = 'automations' || substr(o.name, 6)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."automations"', 'automations' || substr(o.name, 6));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."automations"'::regclass and not t.tgisinternal loop
    if left(o.name, 6) = 'rules_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."automations"'::regclass and x.tgname = 'automations' || substr(o.name, 6)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."automations"', 'automations' || substr(o.name, 6));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."automations"'::regclass loop
    if left(o.name, 6) = 'rules_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'automations' || substr(o.name, 6)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."automations"', o.name, 'automations' || substr(o.name, 6));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."automations"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 6) = 'rules_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'automations' || substr(o.name, 6)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'automations' || substr(o.name, 6));
    end if;
  end loop;
end $$;

-- automations: version 1 to 2. The rule_versions table is automation_versions (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."rule_versions"') is not null and to_regclass('"better_supabase"."automation_versions"') is null then alter table "better_supabase"."rule_versions" rename to "automation_versions"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."automation_versions"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."automation_versions"'::regclass loop
    if left(o.name, 14) = 'rule_versions_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'automation_versions' || substr(o.name, 14)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'automation_versions' || substr(o.name, 14));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."automation_versions"'::regclass loop
    if left(o.name, 14) = 'rule_versions_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."automation_versions"'::regclass and x.polname = 'automation_versions' || substr(o.name, 14)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."automation_versions"', 'automation_versions' || substr(o.name, 14));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."automation_versions"'::regclass and not t.tgisinternal loop
    if left(o.name, 14) = 'rule_versions_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."automation_versions"'::regclass and x.tgname = 'automation_versions' || substr(o.name, 14)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."automation_versions"', 'automation_versions' || substr(o.name, 14));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."automation_versions"'::regclass loop
    if left(o.name, 14) = 'rule_versions_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'automation_versions' || substr(o.name, 14)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."automation_versions"', o.name, 'automation_versions' || substr(o.name, 14));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."automation_versions"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 14) = 'rule_versions_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'automation_versions' || substr(o.name, 14)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'automation_versions' || substr(o.name, 14));
    end if;
  end loop;
end $$;

-- leases: version 2 to 3. The lease_agreements table is leases (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."lease_agreements"') is not null and to_regclass('"better_supabase"."leases"') is null then alter table "better_supabase"."lease_agreements" rename to "leases"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."leases"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."leases"'::regclass loop
    if left(o.name, 17) = 'lease_agreements_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'leases' || substr(o.name, 17)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'leases' || substr(o.name, 17));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."leases"'::regclass loop
    if left(o.name, 17) = 'lease_agreements_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."leases"'::regclass and x.polname = 'leases' || substr(o.name, 17)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."leases"', 'leases' || substr(o.name, 17));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."leases"'::regclass and not t.tgisinternal loop
    if left(o.name, 17) = 'lease_agreements_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."leases"'::regclass and x.tgname = 'leases' || substr(o.name, 17)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."leases"', 'leases' || substr(o.name, 17));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."leases"'::regclass loop
    if left(o.name, 17) = 'lease_agreements_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'leases' || substr(o.name, 17)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."leases"', o.name, 'leases' || substr(o.name, 17));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."leases"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 17) = 'lease_agreements_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'leases' || substr(o.name, 17)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'leases' || substr(o.name, 17));
    end if;
  end loop;
end $$;

-- compliance: version 2 to 3. The policies table is compliance_policies (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."policies"') is not null and to_regclass('"better_supabase"."compliance_policies"') is null then alter table "better_supabase"."policies" rename to "compliance_policies"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."compliance_policies"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."compliance_policies"'::regclass loop
    if left(o.name, 9) = 'policies_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'compliance_policies' || substr(o.name, 9)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'compliance_policies' || substr(o.name, 9));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."compliance_policies"'::regclass loop
    if left(o.name, 9) = 'policies_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."compliance_policies"'::regclass and x.polname = 'compliance_policies' || substr(o.name, 9)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."compliance_policies"', 'compliance_policies' || substr(o.name, 9));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."compliance_policies"'::regclass and not t.tgisinternal loop
    if left(o.name, 9) = 'policies_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."compliance_policies"'::regclass and x.tgname = 'compliance_policies' || substr(o.name, 9)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."compliance_policies"', 'compliance_policies' || substr(o.name, 9));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."compliance_policies"'::regclass loop
    if left(o.name, 9) = 'policies_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'compliance_policies' || substr(o.name, 9)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."compliance_policies"', o.name, 'compliance_policies' || substr(o.name, 9));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."compliance_policies"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 9) = 'policies_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'compliance_policies' || substr(o.name, 9)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'compliance_policies' || substr(o.name, 9));
    end if;
  end loop;
end $$;

-- incidents: version 1 to 2. The status_components table is incident_status_components (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."status_components"') is not null and to_regclass('"better_supabase"."incident_status_components"') is null then alter table "better_supabase"."status_components" rename to "incident_status_components"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."incident_status_components"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."incident_status_components"'::regclass loop
    if left(o.name, 18) = 'status_components_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'incident_status_components' || substr(o.name, 18)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'incident_status_components' || substr(o.name, 18));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."incident_status_components"'::regclass loop
    if left(o.name, 18) = 'status_components_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."incident_status_components"'::regclass and x.polname = 'incident_status_components' || substr(o.name, 18)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."incident_status_components"', 'incident_status_components' || substr(o.name, 18));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."incident_status_components"'::regclass and not t.tgisinternal loop
    if left(o.name, 18) = 'status_components_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."incident_status_components"'::regclass and x.tgname = 'incident_status_components' || substr(o.name, 18)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."incident_status_components"', 'incident_status_components' || substr(o.name, 18));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."incident_status_components"'::regclass loop
    if left(o.name, 18) = 'status_components_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'incident_status_components' || substr(o.name, 18)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."incident_status_components"', o.name, 'incident_status_components' || substr(o.name, 18));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."incident_status_components"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 18) = 'status_components_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'incident_status_components' || substr(o.name, 18)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'incident_status_components' || substr(o.name, 18));
    end if;
  end loop;
end $$;

-- incidents: version 1 to 2. The status_component_history table is incident_status_component_history (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."status_component_history"') is not null and to_regclass('"better_supabase"."incident_status_component_history"') is null then alter table "better_supabase"."status_component_history" rename to "incident_status_component_history"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."incident_status_component_history"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."incident_status_component_history"'::regclass loop
    if left(o.name, 25) = 'status_component_history_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'incident_status_component_history' || substr(o.name, 25)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'incident_status_component_history' || substr(o.name, 25));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."incident_status_component_history"'::regclass loop
    if left(o.name, 25) = 'status_component_history_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."incident_status_component_history"'::regclass and x.polname = 'incident_status_component_history' || substr(o.name, 25)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."incident_status_component_history"', 'incident_status_component_history' || substr(o.name, 25));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."incident_status_component_history"'::regclass and not t.tgisinternal loop
    if left(o.name, 25) = 'status_component_history_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."incident_status_component_history"'::regclass and x.tgname = 'incident_status_component_history' || substr(o.name, 25)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."incident_status_component_history"', 'incident_status_component_history' || substr(o.name, 25));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."incident_status_component_history"'::regclass loop
    if left(o.name, 25) = 'status_component_history_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'incident_status_component_history' || substr(o.name, 25)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."incident_status_component_history"', o.name, 'incident_status_component_history' || substr(o.name, 25));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."incident_status_component_history"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 25) = 'status_component_history_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'incident_status_component_history' || substr(o.name, 25)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'incident_status_component_history' || substr(o.name, 25));
    end if;
  end loop;
end $$;

-- incidents: version 1 to 2. The status_pages table is incident_status_pages (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."status_pages"') is not null and to_regclass('"better_supabase"."incident_status_pages"') is null then alter table "better_supabase"."status_pages" rename to "incident_status_pages"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."incident_status_pages"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."incident_status_pages"'::regclass loop
    if left(o.name, 13) = 'status_pages_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'incident_status_pages' || substr(o.name, 13)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'incident_status_pages' || substr(o.name, 13));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."incident_status_pages"'::regclass loop
    if left(o.name, 13) = 'status_pages_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."incident_status_pages"'::regclass and x.polname = 'incident_status_pages' || substr(o.name, 13)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."incident_status_pages"', 'incident_status_pages' || substr(o.name, 13));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."incident_status_pages"'::regclass and not t.tgisinternal loop
    if left(o.name, 13) = 'status_pages_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."incident_status_pages"'::regclass and x.tgname = 'incident_status_pages' || substr(o.name, 13)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."incident_status_pages"', 'incident_status_pages' || substr(o.name, 13));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."incident_status_pages"'::regclass loop
    if left(o.name, 13) = 'status_pages_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'incident_status_pages' || substr(o.name, 13)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."incident_status_pages"', o.name, 'incident_status_pages' || substr(o.name, 13));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."incident_status_pages"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 13) = 'status_pages_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'incident_status_pages' || substr(o.name, 13)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'incident_status_pages' || substr(o.name, 13));
    end if;
  end loop;
end $$;

-- timeline: version 1 to 2. The activity_entries table is timeline_entries (ADR 0130).
do $$ begin if to_regclass('"better_supabase"."activity_entries"') is not null and to_regclass('"better_supabase"."timeline_entries"') is null then alter table "better_supabase"."activity_entries" rename to "timeline_entries"; end if; end $$;
do $$
declare o record;
begin
  if to_regclass('"better_supabase"."timeline_entries"') is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = '"better_supabase"."timeline_entries"'::regclass loop
    if left(o.name, 17) = 'activity_entries_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'timeline_entries' || substr(o.name, 17)) then
      execute format('alter index %I.%I rename to %I', 'better_supabase', o.name, 'timeline_entries' || substr(o.name, 17));
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = '"better_supabase"."timeline_entries"'::regclass loop
    if left(o.name, 17) = 'activity_entries_' and not exists (select 1 from pg_policy x where x.polrelid = '"better_supabase"."timeline_entries"'::regclass and x.polname = 'timeline_entries' || substr(o.name, 17)) then
      execute format('alter policy %I on %s rename to %I', o.name, '"better_supabase"."timeline_entries"', 'timeline_entries' || substr(o.name, 17));
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = '"better_supabase"."timeline_entries"'::regclass and not t.tgisinternal loop
    if left(o.name, 17) = 'activity_entries_' and not exists (select 1 from pg_trigger x where x.tgrelid = '"better_supabase"."timeline_entries"'::regclass and x.tgname = 'timeline_entries' || substr(o.name, 17)) then
      execute format('alter trigger %I on %s rename to %I', o.name, '"better_supabase"."timeline_entries"', 'timeline_entries' || substr(o.name, 17));
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = '"better_supabase"."timeline_entries"'::regclass loop
    if left(o.name, 17) = 'activity_entries_' and not exists (select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = 'better_supabase' and x.conname = 'timeline_entries' || substr(o.name, 17)) then
      execute format('alter table %s rename constraint %I to %I', '"better_supabase"."timeline_entries"', o.name, 'timeline_entries' || substr(o.name, 17));
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = '"better_supabase"."timeline_entries"'::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if left(o.name, 17) = 'activity_entries_' and not exists (select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = 'better_supabase' and x.relname = 'timeline_entries' || substr(o.name, 17)) then
      execute format('alter sequence %I.%I rename to %I', 'better_supabase', o.name, 'timeline_entries' || substr(o.name, 17));
    end if;
  end loop;
end $$;
