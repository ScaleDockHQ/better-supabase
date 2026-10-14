SET local check_function_bodies = off;

DROP POLICY "comments_insert" ON "better_supabase"."comments";

DROP POLICY "comments_read" ON "better_supabase"."comments";

CREATE TABLE "better_supabase"."metric_points" (
  "tenant_id"    uuid                     NOT NULL,
  "metric"       text                     NOT NULL,
  "grain"        text                     NOT NULL,
  "bucket_start" timestamp with time zone NOT NULL,
  "dims"         jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "value"        numeric                  NOT NULL,
  "count"        bigint                   NOT NULL,
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "metric_points_grain_check" CHECK ((grain = ANY (ARRAY['hour'::text, 'day'::text, 'week'::text, 'month'::text]))),
  CONSTRAINT "metric_points_pkey" PRIMARY KEY (tenant_id, metric, grain, bucket_start, dims)
);

ALTER TABLE "better_supabase"."metric_points"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."search_documents" (
  "tenant_id"    uuid                     NOT NULL,
  "subject_type" text                     NOT NULL,
  "subject_id"   text                     NOT NULL,
  "title"        text,
  "title_search" text                     NOT NULL DEFAULT ''::text,
  "body"         text,
  "url"          text,
  "tsv"          tsvector                 NOT NULL,
  "content_hash" text                     NOT NULL,
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "search_documents_pkey" PRIMARY KEY (subject_type, subject_id)
);

ALTER TABLE "better_supabase"."search_documents"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.metric_definitions()
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."metric_definitions"() $function$;

CREATE OR REPLACE FUNCTION api.metric_series (
  p_metric   text,
  p_tenant   uuid,
  p_from     timestamp with time zone,
  p_until    timestamp with time zone,
  p_grain    text                     DEFAULT 'day'::text,
  p_dims     jsonb                    DEFAULT '{}'::jsonb,
  p_group_by text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."metric_series"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.metric_value (
  p_metric text,
  p_tenant uuid,
  p_from   timestamp with time zone,
  p_until  timestamp with time zone,
  p_dims   jsonb                    DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."metric_value"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.metrics_rollup (
  p_metric text                     DEFAULT NULL::text,
  p_since  timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  p_until  timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."metrics_rollup"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.search (
  q           text,
  types       text[]  DEFAULT NULL::text[],
  tenant      uuid    DEFAULT NULL::uuid,
  max_results integer DEFAULT 20
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."search"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.search_favorites (
  max_results integer DEFAULT 10,
  types       text[]  DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."search_favorites"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.search_recents (
  max_results integer DEFAULT 10,
  types       text[]  DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."search_recents"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.search_refresh (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."search_refresh"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.search_reindex (
  subject_type text DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."search_reindex"($1) $function$;

CREATE OR REPLACE FUNCTION api.search_remove (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."search_remove"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.search_star (
  subject_type text,
  subject_id   text,
  starred      boolean
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."search_star"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.search_touch (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."search_touch"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.can_subject (
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case can_subject.subject_type
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."organization_id", 'customers.read'), false)
          else true
        end)
      );
    else
      return false;
  end case;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comment_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'customers.read'), false)
    else false
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comments_after_write()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_new uuid[];
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."deleted_at" is not null then
    perform better_supabase.audit_event(
    event_type => 'comment.deleted',
    category => 'data',
    target_type => 'comment',
    record_id => new."id"::text,
    tenant => (new."organization_id")::uuid,
    metadata => jsonb_build_object('commentId', new."id", 'organizationId', new."organization_id"::text, 'subjectType', new."subject_type", 'subjectId', new."subject_id", 'authorId', new."author_id")
  );
    return null;
  end if;
  v_new := array(
    select x from unnest(new."mentions") x
    where (tg_op = 'INSERT' or not x = any(old."mentions"))
      and coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'comments.read'), false)
      and case new."subject_type" when 'customer' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'customers.read'), false) else true end
  );
  if tg_op = 'INSERT' then
    null;
  end if;
  if cardinality(v_new) > 0 then
    null;
  end if;
  -- notify() trusts only the service role, so the mention is sent as it,
  -- with the comment's author as the actor; the claims are restored after.
  if cardinality(v_new) > 0 then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'comment.mentioned',
      'tenant', new."organization_id",
      'actor', new."author_id",
      'subject_type', new."subject_type",
      'subject_id', new."subject_id",
      'summary', left(new."body", 140),
      'subject_label', null::text,
      'action_path', null::text,
      'recipients', to_jsonb(v_new),
      'key', 'comment.mentioned:' || new."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('commentId', new."id")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.metric_definitions()
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select '[{"key":"customers","label":"Customers","unit":null,"measure":"count","dimensions":["status"],"grains":[],"tz":"UTC"}]'::jsonb $function$;

CREATE OR REPLACE FUNCTION better_supabase.metric_series (
  p_metric   text,
  p_tenant   uuid,
  p_from     timestamp with time zone,
  p_until    timestamp with time zone,
  p_grain    text                     DEFAULT 'day'::text,
  p_dims     jsonb                    DEFAULT '{}'::jsonb,
  p_group_by text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_source text;
  v_start timestamptz;
  v_buckets integer;
begin
  if p_grain is null or p_grain <> all (array['hour', 'day', 'week', 'month']::text[]) then
    raise exception 'grain must be hour, day, week or month' using errcode = '22023', hint = 'METRIC_GRAIN_INVALID';
  end if;
  if p_from is null or p_until is null or p_until <= p_from then
    raise exception 'the range needs a start before its end' using errcode = '22023', hint = 'METRIC_RANGE_INVALID';
  end if;
  case p_metric
    when 'customers' then
      if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', p_tenant, 'metrics.read'), false)) then
        raise exception 'you cannot read this metric in this organization' using errcode = '42501', hint = 'METRIC_FORBIDDEN';
      end if;
      if exists (
        select 1 from jsonb_object_keys(coalesce(p_dims, '{}'::jsonb)) k
        where k <> all (array['status']::text[])
      ) then
        raise exception 'a filter names a column that is not a dimension of this metric' using errcode = '22023', hint = 'METRIC_DIMENSION_UNKNOWN';
      end if;
      if p_group_by is not null and p_group_by <> all (array['status']::text[]) then
        raise exception 'group_by is not a dimension of this metric' using errcode = '22023', hint = 'METRIC_DIMENSION_UNKNOWN';
      end if;
      v_source := null;
      v_start := date_trunc(p_grain, p_from, 'UTC');
      select count(*) into v_buckets
        from generate_series(v_start at time zone 'UTC', (p_until at time zone 'UTC') - interval '1 microsecond', ('1 ' || p_grain)::interval);
      if v_buckets > 1000 then
        raise exception 'a series returns at most 1000 buckets; pick a coarser grain' using errcode = '22023', hint = 'METRIC_RANGE_TOO_LARGE';
      end if;
      return (
        with source as (
      select s.at, s.dims, s.value, s.count
        from (select t."organization_id" as tenant, t."created_at" as at, jsonb_build_object('status', t."status") as dims, 1::numeric as value, 1::bigint as count
        from "public"."customers" t
        where t."archived_at" is null) s
        where v_source is null
          and s.tenant = p_tenant
          and s.at >= v_start
          and s.at < p_until
          and s.dims @> coalesce(p_dims, '{}'::jsonb)
    ),
        buckets as (
          select b at time zone 'UTC' as bucket
            from generate_series(v_start at time zone 'UTC', (p_until at time zone 'UTC') - interval '1 microsecond', ('1 ' || p_grain)::interval) b
        ),
        grouped as (
          select date_trunc(p_grain, s.at, 'UTC') as bucket,
                 case when p_group_by is null then null else s.dims ->> p_group_by end as grp,
                 sum(s.value) as value,
                 sum(s.count) as count
            from source s
            group by 1, 2
        ),
        per_bucket as (
          select g.bucket, sum(g.value) as value, sum(g.count) as count,
                 jsonb_object_agg(coalesce(g.grp, ''), coalesce(g.value, 0)) as groups
            from grouped g
            group by g.bucket
        )
        select coalesce(jsonb_agg(
          jsonb_build_object('bucket', b.bucket, 'value', coalesce(p.value, 0), 'count', coalesce(p.count, 0))
            || case when p_group_by is null then '{}'::jsonb else jsonb_build_object('groups', coalesce(p.groups, '{}'::jsonb)) end
          order by b.bucket), '[]'::jsonb)
          from buckets b
          left join per_bucket p on p.bucket = b.bucket
      );
    else
      raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.metric_value (
  p_metric text,
  p_tenant uuid,
  p_from   timestamp with time zone,
  p_until  timestamp with time zone,
  p_dims   jsonb                    DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_source text;
begin
  if p_from is null or p_until is null or p_until <= p_from then
    raise exception 'the range needs a start before its end' using errcode = '22023', hint = 'METRIC_RANGE_INVALID';
  end if;
  case p_metric
    when 'customers' then
      if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', p_tenant, 'metrics.read'), false)) then
        raise exception 'you cannot read this metric in this organization' using errcode = '42501', hint = 'METRIC_FORBIDDEN';
      end if;
      if exists (
        select 1 from jsonb_object_keys(coalesce(p_dims, '{}'::jsonb)) k
        where k <> all (array['status']::text[])
      ) then
        raise exception 'a filter names a column that is not a dimension of this metric' using errcode = '22023', hint = 'METRIC_DIMENSION_UNKNOWN';
      end if;
      v_source := null;
      return (
        with source as (
      select s.at, s.dims, s.value, s.count
        from (select t."organization_id" as tenant, t."created_at" as at, jsonb_build_object('status', t."status") as dims, 1::numeric as value, 1::bigint as count
        from "public"."customers" t
        where t."archived_at" is null) s
        where v_source is null
          and s.tenant = p_tenant
          and s.at >= p_from
          and s.at < p_until
          and s.dims @> coalesce(p_dims, '{}'::jsonb)
    ),
        total as (select sum(s.value) as value, sum(s.count) as count from source s)
        select jsonb_build_object('value', coalesce(t.value, 0), 'count', coalesce(t.count, 0))
          from total t
      );
    else
      raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.metrics_rollup (
  p_metric text                     DEFAULT NULL::text,
  p_since  timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  p_until  timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_since timestamptz := coalesce(p_since, now() - interval '3 days');
  v_until timestamptz := coalesce(p_until, now());
  v_from timestamptz;
  v_to timestamptz;
  v_rows integer;
  v_total integer := 0;
begin
  if p_metric is not null and p_metric <> all (array['customers']::text[]) then
    raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
  end if;
  if v_until <= v_since then
    return 0;
  end if;
  perform pg_advisory_xact_lock(hashtext('better_supabase.metrics_rollup'));

  return v_total;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.role_permissions (
  role text
)
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case role
    when 'owner' then array['*']
    when 'admin' then array[
      'customers.read', 'customers.write', 'reports.read',
      'organization.read', 'organization.update',
      'members.read', 'members.invite', 'members.remove', 'members.update_role',
      'billing.read', 'billing.manage', 'audit.read',
      'settings.read', 'settings.update', 'settings.manage',
      'api_keys.manage', 'api_keys.own',
      'comments.read', 'comments.create', 'comments.moderate', 'activity.read',
      'onboarding.read', 'onboarding.complete', 'usage.read', 'usage.record',
      'search.read', 'metrics.read',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run', 'workflow.edit', 'workflow.publish', 'workflow.admin',
      'inbox.read', 'inbox.reply', 'inbox.assign', 'inbox.manage',
      'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'ai_chat.admin',
      'ai.read', 'ai.create', 'ai.share', 'ai.admin'
    ]
    when 'member' then array[
      'customers.read', 'organization.read', 'members.read', 'billing.read',
      'settings.read', 'api_keys.own', 'comments.read', 'comments.create', 'activity.read',
      'onboarding.read', 'usage.read', 'usage.record', 'search.read', 'metrics.read',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run', 'inbox.read', 'inbox.reply',
      'ai_chat.read', 'ai_chat.create', 'ai_chat.share',
      'ai.read', 'ai.create', 'ai.share'
    ]
    else array[]::text[]
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search (
  q           text,
  types       text[]  DEFAULT NULL::text[],
  tenant      uuid    DEFAULT NULL::uuid,
  max_results integer DEFAULT 20
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_q text := btrim(coalesce(search.q, ''));
  v_norm text;
  v_web tsquery;
  v_prefix tsquery;
  v_limit integer := least(greatest(coalesce(search.max_results, 20), 1), 100);
  v_pool integer;
begin
  if length(v_q) > 256 then
    raise exception 'a search query is at most 256 characters' using errcode = '22023', hint = 'SEARCH_QUERY_TOO_LONG';
  end if;
  if v_q = '' then
    return '[]'::jsonb;
  end if;
  v_pool := v_limit * 5;
  v_norm := "better_supabase"."search_normalize"(v_q);
  v_web := websearch_to_tsquery('simple', v_norm);
  select to_tsquery('simple', string_agg(quote_literal(w) || ':*', ' & '))
    into v_prefix
    from regexp_split_to_table(v_norm, '[^[:alnum:]]+') w
    where w <> '';
  return coalesce((
    with text_hits as materialized (
      select h.subject_type, h.subject_id, h.score,
        row_number() over (order by h.score desc) as rank
      from (
        select d."subject_type" as subject_type, d."subject_id" as subject_id,
          2 * coalesce(ts_rank_cd(d."tsv", v_web), 0)
            + coalesce(ts_rank_cd(d."tsv", v_prefix), 0)
            + extensions.similarity(d."title_search", v_norm) as score
        from "better_supabase"."search_documents" d
        where (search.types is null or d."subject_type" = any (search.types))
          and (search.tenant is null or d."tenant_id" = search.tenant)
          and (d."tsv" @@ v_web
            or (v_prefix is not null and d."tsv" @@ v_prefix)
            or d."title_search" operator(extensions.%) v_norm)
        order by score desc
        limit v_pool
      ) h
    ),
    fused as (
      select t.subject_type, t.subject_id, t.score from text_hits t
    ),
    visible as (
      select d."tenant_id" as tenant, d."subject_type" as subject_type, d."subject_id" as subject_id,
        d."title" as title, d."url" as url, d."body" as body, f.score
      from fused f
      join "better_supabase"."search_documents" d on d."subject_type" = f.subject_type and d."subject_id" = f.subject_id
      where "better_supabase"."can_subject"(f.subject_type, f.subject_id, 'read')
      order by f.score desc, f.subject_type, f.subject_id
      limit v_limit
    )
    select jsonb_agg(jsonb_build_object(
      'organizationId', v.tenant,
      'subjectType', v.subject_type,
      'subjectId', v.subject_id,
      'title', v.title,
      'url', v.url,
      'snippet', case when v.body is null then null
        else ts_headline('simple', v.body, coalesce(v_prefix, v_web), 'StartSel="", StopSel="", MaxWords=20, MinWords=8, MaxFragments=1')
      end,
      'score', round(v.score::numeric, 6)
    ) order by v.score desc, v.subject_type, v.subject_id)
    from visible v
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_favorites (
  max_results integer DEFAULT 10,
  types       text[]  DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.starred_at as at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', "better_supabase"."subject_title"(s.subject_type, s.subject_id),
      'url', "better_supabase"."subject_url"(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from "better_supabase"."search_user_state"() s
    where s.starred_at is not null
      and (search_favorites.types is null or s.subject_type = any (search_favorites.types))
      and "better_supabase"."can_subject"(s.subject_type, s.subject_id, 'read')
    order by s.starred_at desc
    limit least(greatest(coalesce(search_favorites.max_results, 10), 1), 100)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_index_row()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_old text := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) ->> tg_argv[1] end;
  v_new text := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) ->> tg_argv[1] end;
begin
  if v_old is not null and v_old is distinct from v_new then
    perform "better_supabase"."search_refresh"(tg_argv[0], v_old);
  end if;
  if v_new is not null then
    perform "better_supabase"."search_refresh"(tg_argv[0], v_new);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_normalize (
  value text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  PARALLEL SAFE
  SET search_path TO ''
  AS $function$
  select lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(value, '')))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_recents (
  max_results integer DEFAULT 10,
  types       text[]  DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.opened_at as at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', "better_supabase"."subject_title"(s.subject_type, s.subject_id),
      'url', "better_supabase"."subject_url"(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from "better_supabase"."search_user_state"() s
    where s.opened_at is not null
      and (search_recents.types is null or s.subject_type = any (search_recents.types))
      and "better_supabase"."can_subject"(s.subject_type, s.subject_id, 'read')
    order by s.opened_at desc
    limit least(greatest(coalesce(search_recents.max_results, 10), 1), 100)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_refresh (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_title text;
  v_body text;
  v_url text;
  v_found boolean := false;
  v_hash text;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  case search_refresh.subject_type
    when 'customer' then
      select s."organization_id", s."name"::text, null, '/customers/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "public"."customers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    else
      raise exception 'this subject type has no search entry in config.subjects' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
  end case;
  if not v_found then
    delete from "better_supabase"."search_documents"
    where "subject_type" = search_refresh.subject_type and "subject_id" = search_refresh.subject_id;
    return false;
  end if;
  v_hash := md5(coalesce(v_title, '') || E'\x1f' || coalesce(v_body, ''));
  insert into "better_supabase"."search_documents" ("tenant_id", "subject_type", "subject_id", "title", "title_search", "body", "url", "tsv", "content_hash", "updated_at")
  values (
    v_tenant, search_refresh.subject_type, search_refresh.subject_id, v_title, "better_supabase"."search_normalize"(v_title), v_body, v_url,
    setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_title)), 'A')
      || setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_body)), 'B'),
    v_hash, now()
  )
  on conflict ("subject_type", "subject_id") do update set
    "tenant_id" = excluded."tenant_id",
    "title" = excluded."title",
    "title_search" = excluded."title_search",
    "body" = excluded."body",
    "url" = excluded."url",
    "tsv" = excluded."tsv",
    "content_hash" = excluded."content_hash",
    "updated_at" = now();
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_reindex (
  subject_type text DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer := 0;
  v_id text;
begin
  if search_reindex.subject_type is null or search_reindex.subject_type = 'customer' then
    for v_id in select s."id"::text from "public"."customers" s loop
      if "better_supabase"."search_refresh"('customer', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_remove (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  delete from "better_supabase"."search_documents"
  where "subject_type" = search_remove.subject_type and "subject_id" = search_remove.subject_id;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_star (
  subject_type text,
  subject_id   text,
  starred      boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'sign in to keep favorites' using errcode = '42501', hint = 'SEARCH_SIGNED_OUT';
  end if;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_touch (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'sign in to keep recents' using errcode = '42501', hint = 'SEARCH_SIGNED_OUT';
  end if;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_user_state()
  RETURNS TABLE (
    subject_type text,
    subject_id   text,
    starred_at   timestamp with time zone,
    opened_at    timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select null::text, null::text, null::timestamptz, null::timestamptz where false
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_title (
  subject_type text,
  subject_id   text
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case subject_title.subject_type
    when 'customer' then
      return (select s."name"::text from "public"."customers" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    else
      return null;
  end case;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_types()
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select '{customer}'::text[]
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_url (
  subject_type text,
  subject_id   text
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case subject_url.subject_type
    when 'customer' then
      return (select '/customers/' || s."id"::text from "public"."customers" s where s."id" = (subject_url.subject_id)::uuid and s."archived_at" is null);
    else
      return null;
  end case;
  return null;
end;
$function$;

CREATE INDEX metric_points_rollup_idx ON better_supabase.metric_points USING btree (metric, grain, bucket_start);

CREATE INDEX search_documents_tenant_idx ON better_supabase.search_documents USING btree (tenant_id, subject_type);

CREATE INDEX search_documents_title_trgm_idx ON better_supabase.search_documents USING gin (title_search extensions.gin_trgm_ops);

CREATE INDEX search_documents_tsv_idx ON better_supabase.search_documents USING gin (tsv);

CREATE TRIGGER bs_search_customer_index
  AFTER INSERT OR DELETE OR UPDATE OF id, organization_id, name, archived_at ON public.customers
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('customer', 'id');

CREATE POLICY "comments_insert" ON "better_supabase"."comments"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((author_id = ( SELECT auth.uid() AS uid)) AND COALESCE(better_supabase.can('tenant'::text, organization_id, 'comments.create'::text), false) AND
    better_supabase.comment_subject_readable(subject_type, subject_id, organization_id) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "comments_read" ON "better_supabase"."comments"
  FOR SELECT
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.tenant_ids_with('comments.read'::text) AS tenant_ids_with)) AND better_supabase.comment_subject_readable(subject_type,
    subject_id, organization_id)));

CREATE POLICY "search_documents_read" ON "better_supabase"."search_documents"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('search.read'::text) AS tenant_ids_with)));

REVOKE ALL ON FUNCTION "api"."metric_definitions"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."metric_definitions"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."metric_series"(text, uuid, timestamp WITH time zone, timestamp WITH time zone, text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."metric_series"(text, uuid, timestamp WITH time zone, timestamp WITH time zone, text, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."metric_value"(text, uuid, timestamp WITH time zone, timestamp WITH time zone, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."metric_value"(text, uuid, timestamp WITH time zone, timestamp WITH time zone, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."metrics_rollup"(text, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."metrics_rollup"(text, timestamp WITH time zone, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "api"."search"(text, text[], uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."search"(text, text[], uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."search_favorites"(integer, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."search_favorites"(integer, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."search_recents"(integer, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."search_recents"(integer, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."search_refresh"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."search_refresh"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."search_reindex"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."search_reindex"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."search_remove"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."search_remove"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."search_star"(text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."search_star"(text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."search_touch"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."search_touch"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."can_subject"(text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."can_subject"(text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."metric_definitions"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."metric_definitions"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."metric_series"(text, uuid, timestamp WITH time zone, timestamp WITH time zone, text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."metric_series"(text, uuid, timestamp WITH time zone, timestamp WITH time zone, text, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."metric_value"(text, uuid, timestamp WITH time zone, timestamp WITH time zone, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."metric_value"(text, uuid, timestamp WITH time zone, timestamp WITH time zone, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."metrics_rollup"(text, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."metrics_rollup"(text, timestamp WITH time zone, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."search"(text, text[], uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."search"(text, text[], uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."search_favorites"(integer, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."search_favorites"(integer, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."search_index_row"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."search_normalize"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."search_normalize"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."search_recents"(integer, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."search_recents"(integer, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."search_refresh"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."search_refresh"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."search_reindex"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."search_reindex"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."search_remove"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."search_remove"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."search_star"(text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."search_star"(text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."search_touch"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."search_touch"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."search_user_state"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."search_user_state"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."subject_title"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."subject_title"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."subject_types"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."subject_types"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."subject_url"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."subject_url"(text, text) TO "authenticated", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."metric_points" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."search_documents" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."search_documents" TO "service_role";
