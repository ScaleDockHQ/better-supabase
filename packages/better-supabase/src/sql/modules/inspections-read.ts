import type { BlockSqlContext } from "../context.ts";

import { pageSize, userGrant } from "../shared.ts";
import { inspectionsSql } from "./inspections-sql.ts";

export function inspectionReads(ctx: BlockSqlContext): string {
  const q = inspectionsSql(ctx);
  const { fn, i, m, f, inspections, members, findings, findingJson } = q;
  const idType = ctx.idType;
  const title = ctx.of("subjects").fn("subject_title");
  const forms = q.forms;
  const s = (column: string): string => forms.col("submissions", column);
  const rel = q.relations;

  const linked =
    rel === undefined
      ? ""
      : (() => {
          const l = (column: string): string => rel.col("relations", column);

          return `
      union
      select y.${l("targetId")} from ${rel.table("relations")} y
      where y.${l("tenant")} = v_row.${i("tenant")} and y.${l("kind")} = 'assesses'
        and y.${l("sourceType")} = ${q.subject} and y.${l("sourceId")} = v_row.${i("id")}::text
        and y.${l("targetType")} = ${q.controlSubject}`;
        })();

  const search = [
    `x.${i("title")} ilike v_search`,
    `x.${i("number")} ilike v_search`,
    ...(["scope", "summary"] as const)
      .filter((column) => q.has("inspections", column))
      .map((column) => `x.${i(column)} ilike v_search`),
  ].join(" or ");

  return `
-- An inspection with its team, its findings, its checklist and the controls
-- it assesses. Readers of inspections and the inspection's members see it.
create or replace function ${fn("get_inspection")}(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${inspections};
begin
  select * into v_row from ${inspections} x where x.${i("id")} = get_inspection.inspection_id;
  if not found or not ${q.sees(`v_row.${i("tenant")}`, `v_row.${i("id")}`)} then
    ${q.missing}
  end if;
  return ${q.inspectionJson("v_row")} || jsonb_build_object(
    'members', coalesce((
      select jsonb_agg(jsonb_build_object('userId', y.${m("user")}, 'role', y.${m("role")}, 'createdAt', y.${m("createdAt")})
        order by case y.${m("role")} when 'lead' then 0 when 'auditor' then 1 when 'auditee' then 2 else 3 end, y.${m("createdAt")})
      from ${members} y where y.${m("tenant")} = v_row.${i("tenant")} and y.${m("inspection")} = v_row.${i("id")}
    ), '[]'::jsonb),
    'findings', coalesce((
      select jsonb_agg(${findingJson("y")} order by y.${f("number")})
      from ${findings} y where y.${f("tenant")} = v_row.${i("tenant")} and y.${f("inspection")} = v_row.${i("id")}
    ), '[]'::jsonb),
    'checklist', case when v_row.${i("checklistForm")} is null then null else jsonb_build_object(
      'formId', v_row.${i("checklistForm")},
      'submissionId', v_row.${i("checklistSubmission")},
      'status', (select y.${s("status")} from ${forms.table("submissions")} y where y.${s("id")} = v_row.${i("checklistSubmission")})
    ) end,
    'assessedControls', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'title', ${title}(${q.controlSubject}, c.id)) order by c.id)
      from (
        select y.${f("control")}::text as id from ${findings} y
        where y.${f("tenant")} = v_row.${i("tenant")} and y.${f("inspection")} = v_row.${i("id")} and y.${f("control")} is not null${linked}
      ) c
    ), '[]'::jsonb)
  );
end;
$$;
${userGrant(`${fn("get_inspection")}(uuid)`)}

-- The organization's inspections, the latest planned first. filters is
-- { programId, kind, status, leadId, from, to (on the planned start),
-- auditeeType, auditeeId, search, limit, offset }. Without inspections.read
-- the caller sees only the inspections they are a member of.
create or replace function ${fn("list_inspections")}(tenant ${idType}, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_inspections.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%' end;
  v_limit integer := ${pageSize("(v_filters ->> 'limit')::integer", 50, 200)};
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_all boolean := ${q.allowed("list_inspections.tenant", q.read)};
begin
  if jsonb_typeof(v_filters) <> 'object' then
    ${q.invalid("filters must be an object")}
  end if;
  if not v_all and auth.uid() is null then
    ${q.forbidden("not allowed to read inspections")}
  end if;
  return coalesce((
    select jsonb_agg(${q.inspectionJson("x")} order by x.${i("plannedStart")} desc nulls last, x.${i("sequence")} desc)
    from (
      select * from ${inspections} x
      where x.${i("tenant")} = list_inspections.tenant
        and (v_all or exists (
          select 1 from ${members} y where y.${m("inspection")} = x.${i("id")} and y.${m("user")} = auth.uid()
        ))
        and (not v_filters ? 'programId' or x.${i("program")} = (v_filters ->> 'programId')::uuid)
        and (not v_filters ? 'kind' or x.${i("kind")} = v_filters ->> 'kind')
        and (not v_filters ? 'status' or x.${i("status")} = v_filters ->> 'status')
        and (not v_filters ? 'leadId' or x.${i("lead")} = (v_filters ->> 'leadId')::uuid)
        and (not v_filters ? 'from' or x.${i("plannedStart")} >= (v_filters ->> 'from')::date)
        and (not v_filters ? 'to' or x.${i("plannedStart")} <= (v_filters ->> 'to')::date)
        and (not v_filters ? 'auditeeType' or x.${i("auditeeType")} = v_filters ->> 'auditeeType')
        and (not v_filters ? 'auditeeId' or x.${i("auditeeId")} = v_filters ->> 'auditeeId')
        and (v_search is null or ${search})
      order by x.${i("plannedStart")} desc nulls last, x.${i("sequence")} desc
      limit v_limit offset v_offset
    ) x
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_inspections")}(${idType}, jsonb)`)}
`;
}
