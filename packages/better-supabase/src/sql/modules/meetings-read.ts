import type { BlockSqlContext } from "../context.ts";

import { pageSize, userGrant } from "../shared.ts";
import { managed, meetingsSql } from "./meetings-sql.ts";

export function meetingReads(ctx: BlockSqlContext): string {
  const q = meetingsSql(ctx);

  const {
    fn,
    m,
    a,
    g,
    d,
    x,
    meetings,
    attendees,
    agenda,
    decisions,
    actions,
    attendeeJson,
    agendaJson,
    decisionJson,
  } = q;

  const idType = ctx.idType;
  const reactions = managed(ctx, "reactions");
  const tasks = ctx.of("tasks");
  const t = (column: string): string => tasks.col("items", column);

  const votes =
    reactions === undefined
      ? ""
      : `, 'votes', ${reactions.fn("vote_tally")}(y.${d("tenant")}, ${q.decisionSubject}, y.${d("id")}::text)`;

  const search = [
    `x.${m("title")} ilike v_search`,
    ...(["location", "summary"] as const)
      .filter((column) => ctx.has("meetings", column))
      .map((column) => `x.${m(column)} ilike v_search`),
  ].join(" or ");

  return `
-- A meeting with its attendees, agenda, decisions (with their vote tally when
-- the reactions block is there) and the tasks opened from it. Readers of
-- meetings and the meeting's attendees see it.
create or replace function ${fn("get_meeting")}(meeting_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${meetings};
begin
  select * into v_row from ${meetings} x where x.${m("id")} = get_meeting.meeting_id;
  if not found or not ${q.sees(`v_row.${m("tenant")}`, `v_row.${m("id")}`)} then
    ${q.missing}
  end if;
  return ${q.meetingJson("v_row")} || jsonb_build_object(
    'attendees', coalesce((
      select jsonb_agg(${attendeeJson("y")}
        order by case y.${a("role")} when 'chair' then 0 when 'secretary' then 1 when 'attendee' then 2 else 3 end, y.${a("createdAt")})
      from ${attendees} y where y.${a("tenant")} = v_row.${m("tenant")} and y.${a("meeting")} = v_row.${m("id")}
    ), '[]'::jsonb),
    'agenda', coalesce((
      select jsonb_agg(${agendaJson("y")} order by y.${g("ordinal")})
      from ${agenda} y where y.${g("tenant")} = v_row.${m("tenant")} and y.${g("meeting")} = v_row.${m("id")}
    ), '[]'::jsonb),
    'decisions', coalesce((
      select jsonb_agg(${decisionJson("y")}${votes ? ` || jsonb_build_object(${votes.slice(2)})` : ""} order by y.${d("createdAt")})
      from ${decisions} y where y.${d("tenant")} = v_row.${m("tenant")} and y.${d("meeting")} = v_row.${m("id")}
    ), '[]'::jsonb),
    'actionItems', coalesce((
      select jsonb_agg(jsonb_build_object('workItemId', z.${tasks.col("items", "id")}, 'title', z.${t("title")}, 'state', z.${t("state")}, 'dueAt', z.${t("dueAt")},
        'agendaItemId', y.${x("agendaItem")}, 'decisionId', y.${x("decision")}) order by y.${x("createdAt")})
      from ${actions} y join ${tasks.table("items")} z on z.${tasks.col("items", "id")} = y.${x("task")}
      where y.${x("tenant")} = v_row.${m("tenant")} and y.${x("meeting")} = v_row.${m("id")}
    ), '[]'::jsonb)
  );
end;
$$;
${userGrant(`${fn("get_meeting")}(uuid)`)}

-- The organization's meetings, the latest first. filters is { kind, status,
-- from, to (on the start time), attendeeId, search, limit, offset }. Without
-- meetings.read the caller sees only the meetings they attend.
create or replace function ${fn("list_meetings")}(tenant ${idType}, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_meetings.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%' end;
  v_limit integer := ${pageSize("(v_filters ->> 'limit')::integer", 50, 200)};
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_all boolean := ${q.allowed("list_meetings.tenant", q.read)};
begin
  if jsonb_typeof(v_filters) <> 'object' then
    ${q.invalid("filters must be an object")}
  end if;
  if not v_all and auth.uid() is null then
    ${q.forbidden("not allowed to read meetings")}
  end if;
  return coalesce((
    select jsonb_agg(${q.meetingJson("x")} order by x.${m("startsAt")} desc, x.${m("id")})
    from (
      select * from ${meetings} x
      where x.${m("tenant")} = list_meetings.tenant
        and (v_all or exists (
          select 1 from ${attendees} y where y.${a("meeting")} = x.${m("id")} and y.${a("user")} = auth.uid()
        ))
        and (not v_filters ? 'kind' or x.${m("kind")} = v_filters ->> 'kind')
        and (not v_filters ? 'status' or x.${m("status")} = v_filters ->> 'status')
        and (not v_filters ? 'from' or x.${m("startsAt")} >= (v_filters ->> 'from')::timestamptz)
        and (not v_filters ? 'to' or x.${m("startsAt")} <= (v_filters ->> 'to')::timestamptz)
        and (not v_filters ? 'attendeeId' or exists (
          select 1 from ${attendees} y where y.${a("meeting")} = x.${m("id")} and y.${a("user")} = (v_filters ->> 'attendeeId')::uuid
        ))
        and (v_search is null or ${search})
      order by x.${m("startsAt")} desc, x.${m("id")}
      limit v_limit offset v_offset
    ) x
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_meetings")}(${idType}, jsonb)`)}
`;
}
