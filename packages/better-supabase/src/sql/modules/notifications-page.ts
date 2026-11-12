import type { BlockSqlContext } from "../context.ts";
import type { NotifyNames } from "./notifications-sql.ts";

import { sqlString } from "../../core/template.ts";
import { pageSize } from "../shared.ts";
import { itemJson } from "./notifications-items.ts";

export const INBOX_MAX_ITEMS = 500;

function names(n: NotifyNames) {
  const e = (logical: string) => n.col("events", logical);
  const r = (logical: string) => n.col("recipients", logical);
  const resolved = n.has("recipients", "resolvedAt");
  const subjectType = n.has("events", "subjectType");
  const subjects = subjectType && n.has("events", "subjectId");

  return { e, r, resolved, subjectType, subjects };
}

function orders(n: NotifyNames): readonly (readonly [string, string])[] {
  const { e, r, resolved } = names(n);

  const statusRank = resolved
    ? `case when rc.${r("resolvedAt")} is not null then 2 when rc.${r("readAt")} is null then 0 else 1 end`
    : `case when rc.${r("readAt")} is null then 0 else 1 end`;

  const newest = `rc.${r("createdAt")} desc, rc.${r("id")} desc`;

  return [
    ["newest", newest],
    ["oldest", `rc.${r("createdAt")}, rc.${r("id")}`],
    ["type", `ev.${e("type")} collate "C", ${newest}`],
    ["type_desc", `ev.${e("type")} collate "C" desc, ${newest}`],
    ...(n.has("events", "subjectLabel")
      ? ([
          [
            "subject",
            `lower(coalesce(ev.${e("subjectLabel")}, '')) collate "C", ${newest}`,
          ],
          [
            "subject_desc",
            `lower(coalesce(ev.${e("subjectLabel")}, '')) collate "C" desc, ${newest}`,
          ],
        ] as const)
      : ([
          ["subject", newest],
          ["subject_desc", newest],
        ] as const)),
    ["status", `${statusRank}, ${newest}`],
    ["status_desc", `${statusRank} desc, ${newest}`],
  ];
}

export function pageFilters(n: NotifyNames): string {
  const { e, r, resolved, subjectType, subjects } = names(n);
  const fn = "notification_page";

  const flag = (key: string, column: string) =>
    `case (g ->> '${key}')::boolean when true then 'rc.${column} is not null' when false then 'rc.${column} is null' end`;

  const list = (key: string, sql: string) =>
    `case when g ? '${key}' then format(${sqlString(sql)}, array(select jsonb_array_elements_text(g -> '${key}'))) end`;

  const groups = [
    list("types", `ev.${e("type")} = any(%L::text[])`),
    list("exclude_types", `ev.${e("type")} <> all(%L::text[])`),
    ...(subjectType
      ? [list("subject_types", `ev.${e("subjectType")} = any(%L::text[])`)]
      : []),
    flag("read", r("readAt")),
    ...(resolved ? [flag("resolved", r("resolvedAt"))] : []),
  ];

  return `
  if ${fn}.exclude_types is not null then
    v_where := v_where || $q$ and ev.${e("type")} <> all($11)$q$;
  end if;${
    subjects
      ? `
  if ${fn}.subject_ids is not null then
    v_where := v_where || $q$ and ev.${e("subjectId")} = any($12)$q$;
  end if;`
      : ""
  }
  if ${fn}.any_of is not null then
    if jsonb_typeof(${fn}.any_of) <> 'array'
      or exists (select 1 from jsonb_array_elements(${fn}.any_of) g where jsonb_typeof(g) <> 'object') then
      raise exception 'any_of is an array of filter objects' using errcode = '22023';
    end if;
    select coalesce(string_agg('(' || concat_ws(' and ', 'true', ${groups.join(", ")}) || ')', ' or '), 'false')
    into v_any
    from jsonb_array_elements(${fn}.any_of) g;
    v_where := v_where || ' and (' || v_any || ')';
  end if;`;
}

export function notificationPage(
  ctx: BlockSqlContext,
  n: NotifyNames,
  parts: { readonly where: string; readonly search: string },
): string {
  const { e, r } = names(n);
  const id = ctx.idType;
  const list = orders(n);

  return `create or replace function ${ctx.fn("notification_page")}(
  tenant ${id} default null,
  status text default 'all',
  types text[] default null,
  subject_types text[] default null,
  search text default null,
  max_items integer default 50,
  skip integer default 0,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false,
  before timestamptz default null,
  before_id uuid default null,
  total_cap integer default 10000,
  exclude_types text[] default null,
  subject_ids text[] default null,
  any_of jsonb default null,
  order_by text default 'newest'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_where text;
  v_any text;
  v_limit integer := ${pageSize("notification_page.max_items", 50, INBOX_MAX_ITEMS)};
  v_order text;
  v_items jsonb;
  v_total bigint;
  v_args_cap integer := notification_page.total_cap;
begin
  v_order := case coalesce(notification_page.order_by, 'newest')
${list.map(([name, sql]) => `    when ${sqlString(name)} then ${sqlString(sql)}`).join("\n")}
  end;
  if v_order is null then
    raise exception 'order_by is one of ${list.map(([name]) => name).join(", ")}, not %', notification_page.order_by using errcode = '22023';
  end if;
  if notification_page.before is not null and coalesce(notification_page.order_by, 'newest') <> 'newest' then
    raise exception 'before pages the newest order; page another order with skip' using errcode = '22023';
  end if;
${parts.where}
  -- One row more than the page says whether another page exists, and the
  -- total stops counting at total_cap (null counts every row), so a large
  -- inbox never counts all of it. Pass before and before_id to page by key
  -- instead of skip.
  execute $q$select coalesce(jsonb_agg(p.item order by p.n), '[]')
  from (
    select row_number() over () as n, q.item
    from (
      select ${itemJson(n)} as item
      from ${n.table("recipients")} rc
      join ${n.table("events")} ev on ev.${e("id")} = rc.${r("event")}
      where $q$ || v_where || $q$
      order by $q$ || v_order || $q$
      offset $13
      limit $14 + 1
    ) q
  ) p$q$
  into v_items
  using auth.uid(), notification_page.tenant, notification_page.types, notification_page.subject_types,
    ${parts.search}, notification_page.read, notification_page.resolved, notification_page.dismissed,
    notification_page.before, coalesce(notification_page.before_id, '00000000-0000-0000-0000-000000000000'::uuid),
    notification_page.exclude_types, notification_page.subject_ids,
    greatest(coalesce(notification_page.skip, 0), 0), v_limit;
  execute $q$select count(*) from (
    select 1 from ${n.table("recipients")} rc
    join ${n.table("events")} ev on ev.${e("id")} = rc.${r("event")}
    where $q$ || v_where || case when v_args_cap is null then '' else format(' limit %s', greatest(v_args_cap, 1)) end || $q$
  ) c$q$
  into v_total
  using auth.uid(), notification_page.tenant, notification_page.types, notification_page.subject_types,
    ${parts.search}, notification_page.read, notification_page.resolved, notification_page.dismissed,
    notification_page.before, coalesce(notification_page.before_id, '00000000-0000-0000-0000-000000000000'::uuid),
    notification_page.exclude_types, notification_page.subject_ids;
  return jsonb_build_object(
    'items', coalesce((select jsonb_agg(x.value order by x.ordinality) from jsonb_array_elements(v_items) with ordinality x(value, ordinality) where x.ordinality <= v_limit), '[]'),
    'hasMore', jsonb_array_length(v_items) > v_limit,
    'limit', v_limit,
    'total', v_total,
    'totalCapped', v_args_cap is not null and v_total >= v_args_cap
  );
end;
$$;
`;
}
