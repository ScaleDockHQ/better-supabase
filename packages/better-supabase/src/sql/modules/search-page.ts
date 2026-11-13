import type { BlockSqlContext } from "../context.ts";

import { fail, userGrant } from "../shared.ts";

/**
 * The `search_page(...)` function: keyset browsing and cursor paging, as the
 * caller.
 */
export function searchPageFunction(
  ctx: BlockSqlContext,
  names: {
    readonly docs: string;
    readonly c: (column: string) => string;
    readonly config: string;
  },
  described: boolean,
): string {
  const { docs, c, config } = names;
  const canSubject = ctx.of("subjects").fn("can_subject");
  const normalize = ctx.fn("search_normalize");
  const name = ctx.fn("search_page");
  const desc = described ? `d.${c("description")} as description, ` : "";

  const columns = `d.${c("tenant")} as tenant, d.${c("subjectType")} as subject_type, d.${c("subjectId")} as subject_id,
          d.${c("title")} as title, d.${c("url")} as url, d.${c("body")} as body, ${desc}d.${c("facets")} as facets, d.${c("sortKey")} as sort_key`;

  const filters = `(search_page.types is null or d.${c("subjectType")} = any (search_page.types))
          and (search_page.tenant is null or d.${c("tenant")} = search_page.tenant)
          and d.${c("facets")} @> v_filter`;

  const collect = (
    headline: string,
  ): string => `select coalesce(jsonb_agg(jsonb_build_object(
        'organizationId', p.tenant,
        'subjectType', p.subject_type,
        'subjectId', p.subject_id,
        'title', p.title,
        'url', p.url,${described ? "\n        'description', p.description," : ""}
        'snippet', ${headline},
        'score', case when p.score is null then null else round(p.score, 6) end,
        'facets', p.facets
      ) order by p.rn) filter (where p.rn <= v_size), '[]'::jsonb),
      count(*) > v_size,
      (select jsonb_build_object('m', v_mode, 'h', v_hash, 'k', l.sort_key, 'i', l.subject_id, 't', l.subject_type, 's', l.score)
        from page l where l.rn = v_size)
    into v_items, v_more, v_last
    from page p;`;

  return `
-- A page of documents as the caller, as { items, nextCursor }. Without q it
-- browses by (sort_key, subject_id); with q it ranks like search() over at
-- most 500 candidates. filter keeps the documents whose facets contain it. The
-- cursor is opaque: pass back what the previous page returned.
create or replace function ${name}(q text default null, types text[] default null, tenant ${ctx.idType} default null, filter jsonb default null, after text default null, page_size integer default 20)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_q text := btrim(coalesce(search_page.q, ''));
  v_mode text := 'b';
  v_norm text;
  v_hash text;
  v_web tsquery;
  v_prefix tsquery;
  v_size integer := least(greatest(coalesce(search_page.page_size, 20), 1), 100);
  v_filter jsonb := coalesce(search_page.filter, '{}'::jsonb);
  v_cur jsonb;
  v_items jsonb;
  v_more boolean;
  v_last jsonb;
  v_next text;
begin
  if length(v_q) > 256 then
    ${fail("SEARCH_QUERY_TOO_LONG", "a search query is at most 256 characters", "22023")}
  end if;
  if jsonb_typeof(v_filter) is distinct from 'object' then
    ${fail("SEARCH_FILTER_INVALID", "filter must be a JSON object of facet values", "22023")}
  end if;
  if v_q <> '' then
    v_mode := 's';
    v_norm := ${normalize}(v_q);
    v_hash := md5(v_norm);
    v_web := websearch_to_tsquery('${config}', v_norm);
    select to_tsquery('${config}', string_agg(quote_literal(w) || ':*', ' & '))
      into v_prefix
      from regexp_split_to_table(v_norm, '[^[:alnum:]]+') w
      where w <> '';
  end if;
  if search_page.after is not null then
    begin
      v_cur := convert_from(decode(rpad(translate(search_page.after, '-_', '+/'), length(search_page.after) + (4 - length(search_page.after) % 4) % 4, '='), 'base64'), 'UTF8')::jsonb;
    exception when others then
      v_cur := null;
    end;
    if v_cur is null or jsonb_typeof(v_cur) is distinct from 'object'
      or v_cur ->> 'm' is distinct from v_mode
      or (v_mode = 's' and v_cur ->> 'h' is distinct from v_hash) then
      ${fail("SEARCH_CURSOR_INVALID", "this cursor does not belong to this query", "22023")}
    end if;
  end if;
  if v_mode = 'b' then
    with lim as (
      select ${columns}, null::numeric as score
      from ${docs} d
      where ${filters}
        and (v_cur is null or (d.${c("sortKey")}, d.${c("subjectId")}, d.${c("subjectType")}) > (v_cur ->> 'k', v_cur ->> 'i', v_cur ->> 't'))
        and ${canSubject}(d.${c("subjectType")}, d.${c("subjectId")}, 'read')
      order by d.${c("sortKey")}, d.${c("subjectId")}, d.${c("subjectType")}
      limit v_size + 1
    ),
    page as (
      select l.*, row_number() over (order by l.sort_key, l.subject_id, l.subject_type) as rn from lim l
    )
    ${collect("null")}
  else
    with pool as materialized (
      select d.${c("subjectType")} as subject_type, d.${c("subjectId")} as subject_id,
        round((2 * coalesce(ts_rank_cd(d.${c("tsv")}, v_web), 0)
          + coalesce(ts_rank_cd(d.${c("tsv")}, v_prefix), 0)
          + extensions.similarity(d.${c("titleSearch")}, v_norm))::numeric, 6) as score
      from ${docs} d
      where ${filters}
        and (d.${c("tsv")} @@ v_web
          or (v_prefix is not null and d.${c("tsv")} @@ v_prefix)
          or d.${c("titleSearch")} operator(extensions.%) v_norm)
      order by score desc, d.${c("subjectType")}, d.${c("subjectId")}
      limit 500
    ),
    lim as (
      select ${columns}, h.score
      from pool h
      join ${docs} d on d.${c("subjectType")} = h.subject_type and d.${c("subjectId")} = h.subject_id
      where (v_cur is null
          or h.score < (v_cur ->> 's')::numeric
          or (h.score = (v_cur ->> 's')::numeric and (h.subject_type, h.subject_id) > (v_cur ->> 't', v_cur ->> 'i')))
        and ${canSubject}(h.subject_type, h.subject_id, 'read')
      order by h.score desc, h.subject_type, h.subject_id
      limit v_size + 1
    ),
    page as (
      select l.*, row_number() over (order by l.score desc, l.subject_type, l.subject_id) as rn from lim l
    )
    ${collect(`case when p.body is null then null
          else ts_headline('${config}', p.body, coalesce(v_prefix, v_web), 'StartSel="", StopSel="", MaxWords=20, MinWords=8, MaxFragments=1')
        end`)}
  end if;
  if v_more then
    v_next := translate(encode(convert_to(v_last::text, 'UTF8'), 'base64'), E'+/=\\n', '-_');
  end if;
  return jsonb_build_object('items', v_items, 'nextCursor', v_next);
end;
$$;
${userGrant(`${name}(text, text[], ${ctx.idType}, jsonb, text, integer)`)}`;
}
