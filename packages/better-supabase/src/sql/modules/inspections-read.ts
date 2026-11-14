import type { BlockSqlContext } from "../context.ts";

import {
  filterAny,
  filterFirst,
  listBody,
  listDeclare,
} from "../list-template.ts";
import { userGrant } from "../shared.ts";
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

  const list = {
    name: "list_inspections",
    from: inspections,
    alias: "x",
    where: [
      `x.${i("tenant")} = list_inspections.tenant`,
      `(v_all or exists (
          select 1 from ${members} y where y.${m("inspection")} = x.${i("id")} and y.${m("user")} = auth.uid()
        ))`,
      filterAny("programId", `x.${i("program")}`, "uuid"),
      filterAny("kind", `x.${i("kind")}`),
      filterAny("status", `x.${i("status")}`),
      filterAny("leadId", `x.${i("lead")}`, "uuid"),
      `(${filterFirst("from")} is null or x.${i("plannedStart")} >= ${filterFirst("from")}::date)`,
      `(${filterFirst("to")} is null or x.${i("plannedStart")} <= ${filterFirst("to")}::date)`,
      filterAny("auditeeType", `x.${i("auditeeType")}`),
      filterAny("auditeeId", `x.${i("auditeeId")}`),
      `(v_search is null or ${search})`,
    ],
    keys: [
      {
        expr: `coalesce(x.${i("plannedStart")}, '-infinity'::date)`,
        dir: "desc",
        type: "date",
      },
      { expr: `x.${i("sequence")}`, dir: "desc", type: "bigint" },
      { expr: `x.${i("id")}`, dir: "asc", type: "uuid" },
    ],
    sorts: {
      plannedStart: [
        {
          expr: `coalesce(x.${i("plannedStart")}, '-infinity'::date)`,
          dir: "desc",
          type: "date",
        },
        { expr: `x.${i("sequence")}`, dir: "desc", type: "bigint" },
        { expr: `x.${i("id")}`, dir: "asc", type: "uuid" },
      ],
      number: [
        { expr: `x.${i("sequence")}`, dir: "desc", type: "bigint" },
        { expr: `x.${i("id")}`, dir: "asc", type: "uuid" },
      ],
    },
    facets: { status: `x.${i("status")}`, kind: `x.${i("kind")}` },
    rowJson: q.inspectionJson("x"),
    invalid: q.invalid,
  } as const;

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
-- { programId, kind, status, leadId, auditeeType, auditeeId (each a value or a
-- list of them), from, to (on the planned start), search, sort, direction,
-- facet, count, limit, after, offset, paged, total, totalCap } (ADR 0749). Without inspections.read
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
  ${listDeclare(list)}
  v_all boolean := ${q.allowed("list_inspections.tenant", q.read)};
begin
  if jsonb_typeof(v_filters) <> 'object' then
    ${q.invalid("filters must be an object")}
  end if;
  if not v_all and auth.uid() is null then
    ${q.forbidden("not allowed to read inspections")}
  end if;
  ${listBody(list)}
end;
$$;
${userGrant(`${fn("list_inspections")}(${idType}, jsonb)`)}
`;
}
