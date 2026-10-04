SET local check_function_bodies = off;

DROP TRIGGER "contacts_set_updated_at" ON "public"."contacts";

DROP TRIGGER "customers_set_updated_at" ON "public"."customers";

DROP TRIGGER "locations_set_updated_at" ON "public"."locations";

DROP TRIGGER "notes_set_updated_at" ON "public"."notes";

DROP TRIGGER "organizations_set_updated_at" ON "public"."organizations";

DROP FUNCTION "public"."set_updated_at"();

CREATE TABLE "better_supabase"."kit_modules" (
  "name"         text                     NOT NULL,
  "version"      integer                  NOT NULL,
  "mode"         text                     NOT NULL,
  "installed_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "kit_modules_pkey" PRIMARY KEY (name)
);

ALTER TABLE "better_supabase"."kit_modules"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."rate_limit_rules" (
  "scope"        text     NOT NULL,
  "max_requests" integer  NOT NULL,
  "period"       interval NOT NULL,
  "key_claim"    text     NOT NULL DEFAULT 'sub'::text,
  CONSTRAINT "rate_limit_rules_max_requests_check" CHECK ((max_requests > 0)),
  CONSTRAINT "rate_limit_rules_period_check" CHECK ((period > '00:00:00'::interval)),
  CONSTRAINT "rate_limit_rules_pkey" PRIMARY KEY (scope)
);

ALTER TABLE "better_supabase"."rate_limit_rules"
  ENABLE ROW LEVEL SECURITY;

CREATE UNLOGGED TABLE "better_supabase"."rate_limits" (
  "scope"        text                     NOT NULL,
  "key"          text                     NOT NULL,
  "window_start" timestamp with time zone NOT NULL,
  "hits"         integer                  NOT NULL,
  CONSTRAINT "rate_limits_pkey" PRIMARY KEY (scope, key)
);

ALTER TABLE "better_supabase"."rate_limits"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."customer_tags"
  ADD COLUMN "created_at" timestamp WITH time zone NOT NULL DEFAULT now();

ALTER TABLE "public"."notifications"
  ADD COLUMN "updated_at" timestamp WITH time zone NOT NULL DEFAULT now();

ALTER TABLE "public"."tags"
  ADD COLUMN "created_at" timestamp WITH time zone NOT NULL DEFAULT now();

ALTER TABLE "public"."tags"
  ADD COLUMN "updated_at" timestamp WITH time zone NOT NULL DEFAULT now();

CREATE OR REPLACE FUNCTION better_supabase.check_request()
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  method text := current_setting('request.method', true);
  path text := current_setting('request.path', true);
  claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  rule better_supabase.rate_limit_rules;
  caller text;
  used integer;
  started timestamptz;
  retry integer;
begin
  if method is null or method not in ('POST', 'PATCH', 'PUT', 'DELETE') then
    return;
  end if;
  if claims ->> 'role' = 'service_role' then
    return;
  end if;
  for rule in
    select * from better_supabase.rate_limit_rules r where r.scope in ('*', path) order by r.scope
  loop
    caller := coalesce(
      claims ->> rule.key_claim,
      'ip:' || coalesce(nullif(trim(reverse(split_part(reverse(headers ->> 'x-forwarded-for'), ',', 1))), ''), 'unknown')
    );
    insert into better_supabase.rate_limits as l (scope, key, window_start, hits)
    values (rule.scope, caller, now(), 1)
    on conflict on constraint rate_limits_pkey do update set
      window_start = case when l.window_start + rule.period <= now() then now() else l.window_start end,
      hits = case when l.window_start + rule.period <= now() then 1 else l.hits + 1 end
    returning l.hits, l.window_start into used, started;
    if used > rule.max_requests then
      retry := greatest(1, ceil(extract(epoch from started + rule.period - now()))::integer);
      raise sqlstate 'PGRST' using
        message = json_build_object(
          'code', 'BS429',
          'message', format('Rate limit for %s exceeded: %s writes per %s', rule.scope, rule.max_requests, rule.period),
          'details', format('Retry after %s seconds.', retry),
          'hint', null
        )::text,
        detail = json_build_object(
          'status', 429,
          'status_text', 'Too Many Requests',
          'headers', json_build_object('Retry-After', retry::text)
        )::text;
    end if;
  end loop;
end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_rate_limits (
  batch integer DEFAULT 10000
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with expired as (
    select l.scope, l.key from better_supabase.rate_limits l
    left join better_supabase.rate_limit_rules r on r.scope = l.scope
    where r.scope is null or l.window_start + r.period <= now()
    limit batch
  ),
  purged as (
    delete from better_supabase.rate_limits l
    using expired e
    where l.scope = e.scope and l.key = e.key
    returning 1
  )
  select count(*)::integer from purged
$function$;

CREATE OR REPLACE FUNCTION better_supabase.replace_equivalent_triggers (
  target          regclass,
  kit_trigger     text,
  pattern         text,
  replace_trigger boolean
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  found record;
begin
  for found in
    select t.tgname as name, p.proname as fn
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = replace_equivalent_triggers.target
      and not t.tgisinternal
      and t.tgname <> replace_equivalent_triggers.kit_trigger
      and p.proname ~* replace_equivalent_triggers.pattern
  loop
    if replace_trigger then
      execute format('drop trigger %I on %s', found.name, target);
    else
      raise warning '% already has trigger % (%), which does what % does. Pass replace_trigger => true to drop it.',
        target, found.name, found.fn, kit_trigger;
    end if;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_rate_limit (
  scope        text,
  max_requests integer,
  period       interval DEFAULT '00:01:00'::interval,
  key_claim    text     DEFAULT 'sub'::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if max_requests is null then
    delete from better_supabase.rate_limit_rules r where r.scope = set_rate_limit.scope;
    delete from better_supabase.rate_limits l where l.scope = set_rate_limit.scope;
    return;
  end if;
  insert into better_supabase.rate_limit_rules as r (scope, max_requests, period, key_claim)
  values (scope, max_requests, period, key_claim)
  on conflict on constraint rate_limit_rules_pkey do update
    set max_requests = excluded.max_requests, period = excluded.period, key_claim = excluded.key_claim;
end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_updated_at()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  new := jsonb_populate_record(
    new,
    jsonb_build_object(coalesce(tg_argv[0], 'updated_at'), now())
  );
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.track_realtime (
  target        regclass,
  tenant_column text     DEFAULT NULL::text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if tenant_column is not null and not exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = target and a.attname = tenant_column and a.attnum > 0 and not a.attisdropped
  ) then
    raise exception '% has no column %', target, tenant_column
      using errcode = '42703',
        hint = 'Add the tenant column, or list the table in realtime.global to broadcast it to every signed-in user';
  end if;
  execute format('drop trigger if exists bs_realtime on %s', target);
  execute format('drop trigger if exists bs_realtime_insert on %s', target);
  execute format('drop trigger if exists bs_realtime_update on %s', target);
  execute format('drop trigger if exists bs_realtime_delete on %s', target);
  if tenant_column is null then
    execute format(
      'create trigger bs_realtime after insert or update or delete on %s for each statement execute function better_supabase.broadcast_changes()',
      target
    );
    return;
  end if;
  execute format(
    'create trigger bs_realtime_insert after insert on %s referencing new table as new_rows for each statement execute function better_supabase.broadcast_changes(%L)',
    target, tenant_column
  );
  execute format(
    'create trigger bs_realtime_update after update on %s referencing old table as old_rows new table as new_rows for each statement execute function better_supabase.broadcast_changes(%L)',
    target, tenant_column
  );
  execute format(
    'create trigger bs_realtime_delete after delete on %s referencing old table as old_rows for each statement execute function better_supabase.broadcast_changes(%L)',
    target, tenant_column
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.track_updated_at (
  target          regclass,
  column_name     text     DEFAULT 'updated_at'::text,
  replace_trigger boolean  DEFAULT false
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  perform better_supabase.replace_equivalent_triggers(
    target, 'bs_updated_at', 'updated_at|moddatetime|touch', replace_trigger
  );
  execute format('drop trigger if exists bs_updated_at on %s', target);
  execute format(
    'create trigger bs_updated_at before update on %s for each row execute function better_supabase.set_updated_at(%L)',
    target,
    column_name
  );
end;
$function$;

CREATE INDEX contacts_organization_id_email_idx ON public.contacts USING btree (organization_id, lower(email));

CREATE TRIGGER contacts_set_updated_at
  BEFORE UPDATE ON public.contacts
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at();

CREATE TRIGGER customers_set_updated_at
  BEFORE UPDATE ON public.customers
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at();

CREATE TRIGGER locations_set_updated_at
  BEFORE UPDATE ON public.locations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at();

CREATE TRIGGER notes_set_updated_at
  BEFORE UPDATE ON public.notes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at();

CREATE TRIGGER notifications_set_updated_at
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at();

CREATE TRIGGER organizations_set_updated_at
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at();

CREATE TRIGGER tags_set_updated_at
  BEFORE UPDATE ON public.tags
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at();

REVOKE ALL ON FUNCTION "better_supabase"."check_request"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."check_request"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_rate_limits"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_rate_limits"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."replace_equivalent_triggers"(regclass, text, text, boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."set_rate_limit"(text, integer, interval, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_rate_limit"(text, integer, interval, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."track_updated_at"(regclass, text, boolean) FROM PUBLIC;

GRANT SELECT ON TABLE "better_supabase"."kit_modules" TO "service_role";
