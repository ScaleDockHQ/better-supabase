SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.finance_list (
  entity  text,
  tenant  uuid,
  q       text    DEFAULT NULL::text,
  filters jsonb   DEFAULT '{}'::jsonb,
  sort    text    DEFAULT NULL::text,
  after   text    DEFAULT NULL::text,
  lim     integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  spec jsonb := api.finance_list_spec(entity);
  chosen jsonb;
  wheres text[] := array['t.tenant_id = $1'];
  base text[];
  facet_wheres jsonb := '{}'::jsonb;
  facet record;
  counts jsonb := '{}'::jsonb;
  counted jsonb;
  capped boolean := false;
  this_capped boolean;
  terms text[];
  cur jsonb := case when after is null or after = '' then null else after::jsonb end;
  op text;
  size integer := least(greatest(coalesce(lim, 50), 1), 200);
  statement text;
  fetched jsonb;
  kept jsonb;
  last_row jsonb;
begin
  if spec is null then
    raise exception 'unknown finance entity %', entity using errcode = '22023', hint = 'FINANCE_UNKNOWN_ENTITY';
  end if;

  chosen := coalesce(spec -> 'sorts' -> coalesce(sort, 'default'), spec -> 'sorts' -> 'default');
  op := case when chosen ->> 'dir' = 'desc' then '<' else '>' end;

  for facet in select key, value from jsonb_each(coalesce(filters, '{}'::jsonb)) loop
    if spec -> 'facets' ? facet.key and jsonb_typeof(facet.value) = 'array'
      and jsonb_array_length(facet.value) > 0 then
      facet_wheres := facet_wheres || jsonb_build_object(facet.key, format(
        '(%s)::text = any (%L::text[])',
        spec -> 'facets' ->> facet.key,
        array(select jsonb_array_elements_text(facet.value))));
    end if;
  end loop;

  if q is not null and btrim(q) <> '' then
    select array_agg(format('%s::text ilike $2', term))
      into terms
      from jsonb_array_elements_text(spec -> 'search') as term;

    wheres := wheres || ('(' || array_to_string(terms, ' or ') || ')');
  end if;

  base := wheres;

  wheres := wheres || array(select value #>> '{}' from jsonb_each(facet_wheres));

  if cur is not null then
    wheres := wheres || format(
      '((%s), t.id) %s ($3::%s, $4::uuid)',
      chosen ->> 'expr', op, chosen ->> 'cast');
  end if;

  statement := format(
    $s$select coalesce(jsonb_agg(x order by x.n), '[]'::jsonb) from (
      select row_number() over (order by (%2$s) %5$s, t.id %5$s) as n, (%1$s) as item,
        ((%2$s))::text as k, t.id as id
      from %3$s where %4$s
      order by (%2$s) %5$s, t.id %5$s limit %6$s) x$s$,
    spec ->> 'item', chosen ->> 'expr', spec ->> 'from',
    array_to_string(wheres, ' and '), chosen ->> 'dir', size + 1);

  execute statement into fetched
    using tenant, '%' || coalesce(q, '') || '%',
      cur ->> 'k', (cur ->> 'id')::uuid;

  select coalesce(jsonb_agg(r -> 'item' order by ord), '[]'::jsonb)
    into kept
    from jsonb_array_elements(fetched) with ordinality as e(r, ord)
    where ord <= size;

  last_row := case
    when jsonb_array_length(fetched) > size then fetched -> (size - 1)
    else null end;

  -- Each facet counts its values under every other filter, over at most 1,000
  -- rows (a capped count), on the first page only.
  if cur is null then
    for facet in select key, value from jsonb_each_text(spec -> 'facets') loop
      execute format(
        $c$select coalesce(jsonb_object_agg(v, n), '{}'::jsonb), coalesce(sum(n) >= 1000, false) from (
          select v, count(*) as n from (
            select (%1$s)::text as v from %2$s where %3$s limit 1000) s
          where v is not null group by v) g$c$,
        facet.value, spec ->> 'from',
        array_to_string(base || array(
          select w.value #>> '{}' from jsonb_each(facet_wheres) w where w.key <> facet.key), ' and '))
        into counted, this_capped
        using tenant, '%' || coalesce(q, '') || '%';

      capped := capped or this_capped;
      counts := counts || jsonb_build_object(facet.key, counted);
    end loop;
  end if;

  return jsonb_build_object(
    'items', kept,
    'nextCursor', case when last_row is null then null
      else jsonb_build_object('k', last_row ->> 'k', 'id', last_row ->> 'id')::text end,
    'facetCounts', case when cur is null then counts end,
    'facetCountsCapped', case when cur is null then capped end);
end;
$function$;
