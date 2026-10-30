import type { BlockSqlContext } from "../context.ts";
import type { InspectionsSql } from "./inspections-sql.ts";

import { sqlString } from "../../core/template.ts";
import { fail, userGrant } from "../shared.ts";
import { inspectionsSql } from "./inspections-sql.ts";

const TEXTS = [
  ["description", 10_000],
  ["clause", 200],
  ["evidence", 10_000],
] as const;

/** The source a raised case gets: `inspection` when the cases block takes it. */
function caseSource(cases: BlockSqlContext): string {
  const sources = cases.option("sources");

  if (!Array.isArray(sources) || sources.includes("inspection")) {
    return "inspection";
  }

  return sources.includes("internal") ? "internal" : String(sources[0]);
}

/** Links inspection `inspection` to control `control` as `assesses`. */
function assessesLink(
  q: InspectionsSql,
  tenant: string,
  inspection: string,
  control: string,
): string {
  const rel = q.relations;

  if (rel === undefined) {
    return "";
  }

  const l = (column: string): string => rel.col("relations", column);

  return `
  if ${control} is not null then
    insert into ${rel.table("relations")} (${l("tenant")}, ${l("kind")}, ${l("sourceType")}, ${l("sourceId")}, ${l("targetType")}, ${l("targetId")}, ${l("createdBy")})
    select ${tenant}, 'assesses', ${q.subject}, ${inspection}::text, ${q.controlSubject}, ${control}::text, auth.uid()
    where not exists (
      select 1 from ${rel.table("relations")} y
      where y.${l("tenant")} = ${tenant} and y.${l("kind")} = 'assesses' and y.${l("sourceType")} = ${q.subject}
        and y.${l("sourceId")} = ${inspection}::text and y.${l("targetType")} = ${q.controlSubject} and y.${l("targetId")} = ${control}::text
    );
  end if;`;
}

/** Refuses a control that is not one of the organization's. */
function controlCheck(
  q: InspectionsSql,
  tenant: string,
  control: string,
): string {
  const c = q.compliance;

  if (c === undefined) {
    return `if ${control} is not null then
    ${q.invalid("controlId needs the compliance block")}
  end if;`;
  }

  return `if ${control} is not null and not exists (
    select 1 from ${c.table("controls")} y
    where y.${c.col("controls", "id")} = ${control} and y.${c.col("controls", "tenant")}::text = ${tenant}::text
  ) then
    ${q.invalid("the control is not a control of this organization")}
  end if;`;
}

/** Loads the finding `v_row` and its inspection `v_inspection` for a writer. */
function loadFinding(q: InspectionsSql, func: string, what: string): string {
  const { i, f, inspections, findings } = q;

  return `select * into v_row from ${findings} x where x.${f("id")} = ${func}.finding_id for update;
  if not found then
    ${q.findingMissing}
  end if;
  select * into v_inspection from ${inspections} x where x.${i("id")} = v_row.${f("inspection")} for update;
  if not ${q.acts(`v_inspection.${i("tenant")}`, `v_inspection.${i("id")}`, ["lead", "auditor"])} then
    ${q.forbidden(`not allowed to ${what}`)}
  end if;
  if v_inspection.${i("status")} not in ('in_progress', 'reporting') then
    ${q.invalid("findings change while the inspection is in progress or reporting")}
  end if;`;
}

function raiseCase(q: InspectionsSql): string {
  const { fn, i, f, findings, findingJson } = q;
  const cases = q.cases;

  const body =
    cases === undefined
      ? `  ${fail("INSPECTION_CASES_NOT_INSTALLED", "raising a case needs the cases block", "0A000")}`
      : (() => {
          const k = (column: string): string => cases.col("kinds", column);
          const c = (column: string): string => cases.col("cases", column);

          const kindId = `select y.${k("id")} into v_kind from ${cases.table("kinds")} y
  where y.${k("tenant")}::text = v_row.${f("tenant")}::text and y.${k("key")} = raise_inspection_finding_case.kind and y.${k("archivedAt")} is null;`;

          return `  ${loadFinding(q, "raise_inspection_finding_case", "raise a case for this finding")}
  if v_row.${f("case")} is not null then
    ${q.invalid("the finding already has a case")}
  end if;
  ${kindId}
  if v_kind is null then
    perform ${cases.fn("ensure_case_kinds")}(v_row.${f("tenant")});
    ${kindId}
  end if;
  if v_kind is null then
    ${q.invalid("no such case kind in this organization")}
  end if;
  v_case := ${cases.fn("open_case_as")}(v_kind, jsonb_build_object(
    'title', left(v_inspection.${i("number")} || ': ' || v_row.${f("title")}, 200),
    'description', ${q.of("findings", "v_row", "description")},
    'source', ${sqlString(caseSource(cases))},
    'occurredAt', coalesce(v_inspection.${i("startedAt")}, now()),
    'ownerId', raise_inspection_finding_case.owner_id,
    'originType', ${q.findingSubject},
    'originId', v_row.${f("id")}::text
  ), auth.uid());
  update ${findings} x set ${f("case")} = v_case.${c("id")}, ${f("updatedAt")} = now()
  where x.${f("id")} = v_row.${f("id")}
  returning * into v_row;
  ${q.recordFinding("inspection_finding.case_raised", "v_row", "case raised for finding", `, 'caseId', v_row.${f("case")}`)}
  return ${findingJson("v_row")};`;
        })();

  const declare =
    cases === undefined
      ? ""
      : `
declare
  v_row ${findings};
  v_inspection ${q.inspections};
  v_kind uuid;
  v_case ${cases.table("cases")};`;

  return `
-- Opens a case of kind (default finding) for a finding, linked back to it, as
-- the inspection's lead or an auditor. The case's own rules then apply.
create or replace function ${fn("raise_inspection_finding_case")}(finding_id uuid, kind text default 'finding', owner_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable${declare}
begin
${body}
end;
$$;
${userGrant(`${fn("raise_inspection_finding_case")}(uuid, text, uuid)`)}
`;
}

export function inspectionFindingFunctions(ctx: BlockSqlContext): string {
  const q = inspectionsSql(ctx);
  const { fn, i, f, inspections, findings, findingJson, has } = q;

  const typeCheck = `if v_type is null or not (v_type = any (${q.findingTypes})) then
    ${fail("INSPECTION_FINDING_TYPE_UNKNOWN", "the type is not one of options.findingTypes", "22023")}
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    ${q.invalid("a finding needs a title of 1 to 300 characters")}
  end if;`;

  const textCheck = (value: (column: string) => string): string =>
    TEXTS.map(([column, max]) =>
      has("findings", column)
        ? `
  if length(${value(column)}) > ${String(max)} then
    ${q.invalid(`${column} is at most ${String(max)} characters`)}
  end if;`
        : `
  if nullif(trim(${value(column)}), '') is not null then
    ${q.invalid(`the findings table has no ${column} column`)}
  end if;`,
    ).join("");

  const texts = TEXTS.map(([column]) => column).filter((column) =>
    has("findings", column),
  );

  const createdBy = has("findings", "createdBy");

  return `
-- Adds a finding to an inspection in progress or reporting, as its lead or an
-- auditor. type is one of options.findingTypes; control_id names the
-- compliance control it concerns, which the inspection then assesses.
create or replace function ${fn("add_inspection_finding")}(inspection_id uuid, type text, title text, description text default null, clause text default null, control_id uuid default null, evidence text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_inspection ${inspections};
  v_row ${findings};
  v_type text := add_inspection_finding.type;
  v_title text := trim(add_inspection_finding.title);
  v_number integer;
begin
  select * into v_inspection from ${inspections} x where x.${i("id")} = add_inspection_finding.inspection_id for update;
  if not found then
    ${q.missing}
  end if;
  if not ${q.acts(`v_inspection.${i("tenant")}`, `v_inspection.${i("id")}`, ["lead", "auditor"])} then
    ${q.forbidden("not allowed to add findings to this inspection")}
  end if;
  if v_inspection.${i("status")} not in ('in_progress', 'reporting') then
    ${q.invalid("findings change while the inspection is in progress or reporting")}
  end if;
  ${typeCheck}${textCheck((column) => `add_inspection_finding.${column}`)}
  ${controlCheck(q, `v_inspection.${i("tenant")}`, "add_inspection_finding.control_id")}
  ${ctx.hook("before_inspection_finding_create", [
    ["uuid", "add_inspection_finding.inspection_id"],
    [
      "jsonb",
      "jsonb_build_object('type', add_inspection_finding.type, 'title', add_inspection_finding.title, 'controlId', add_inspection_finding.control_id)",
    ],
  ])}
  select coalesce(max(y.${f("number")}), 0) + 1 into v_number from ${findings} y where y.${f("inspection")} = v_inspection.${i("id")};
  insert into ${findings} (${f("tenant")}, ${f("inspection")}, ${f("number")}, ${f("type")}, ${f("title")}${texts.map((column) => `, ${f(column)}`).join("")}, ${f("control")}${createdBy ? `, ${f("createdBy")}` : ""})
  values (v_inspection.${i("tenant")}, v_inspection.${i("id")}, v_number, v_type, v_title${texts.map((column) => `, nullif(trim(add_inspection_finding.${column}), '')`).join("")}, add_inspection_finding.control_id${createdBy ? ", auth.uid()" : ""})
  returning * into v_row;${assessesLink(q, `v_row.${f("tenant")}`, `v_row.${f("inspection")}`, `v_row.${f("control")}`)}
  ${q.recordFinding("inspection_finding.created", "v_row", "finding added")}
  ${ctx.hook("after_inspection_finding_create", [["uuid", `v_row.${f("id")}`]])}
  return ${findingJson("v_row")};
end;
$$;
${userGrant(`${fn("add_inspection_finding")}(uuid, text, text, text, text, uuid, text)`)}

-- Changes a finding's type, title, description, clause, controlId or evidence.
create or replace function ${fn("update_inspection_finding")}(finding_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${findings};
  v_inspection ${inspections};
  v_type text;
  v_title text;
  v_control uuid;
begin
  ${loadFinding(q, "update_inspection_finding", "change this finding")}
  if jsonb_typeof(update_inspection_finding.changes) is distinct from 'object' then
    ${q.invalid("changes must be an object")}
  end if;
  v_type := coalesce(update_inspection_finding.changes ->> 'type', v_row.${f("type")});
  v_title := case when update_inspection_finding.changes ? 'title' then trim(update_inspection_finding.changes ->> 'title') else v_row.${f("title")} end;
  v_control := case when update_inspection_finding.changes ? 'controlId' then nullif(update_inspection_finding.changes ->> 'controlId', '')::uuid else v_row.${f("control")} end;
  ${typeCheck}${textCheck((column) => `(update_inspection_finding.changes ->> '${column}')`)}
  ${controlCheck(q, `v_row.${f("tenant")}`, "v_control")}
  update ${findings} x set
    ${f("type")} = v_type,
    ${f("title")} = v_title,${texts.map((column) => `\n    ${f(column)} = case when update_inspection_finding.changes ? '${column}' then nullif(trim(update_inspection_finding.changes ->> '${column}'), '') else x.${f(column)} end,`).join("")}
    ${f("control")} = v_control,
    ${f("updatedAt")} = now()
  where x.${f("id")} = v_row.${f("id")}
  returning * into v_row;${assessesLink(q, `v_row.${f("tenant")}`, `v_row.${f("inspection")}`, `v_row.${f("control")}`)}
  ${q.recordFinding("inspection_finding.updated", "v_row", "finding updated")}
  return ${findingJson("v_row")};
end;
$$;
${userGrant(`${fn("update_inspection_finding")}(uuid, jsonb)`)}

-- Deletes a finding that has no case.
create or replace function ${fn("delete_inspection_finding")}(finding_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${findings};
  v_inspection ${inspections};
begin
  ${loadFinding(q, "delete_inspection_finding", "delete this finding")}
  if v_row.${f("case")} is not null then
    ${fail("INSPECTION_FINDING_HAS_CASE", "a finding with a case can't be deleted", "55000")}
  end if;
  delete from ${findings} x where x.${f("id")} = v_row.${f("id")};
  ${q.recordFinding("inspection_finding.deleted", "v_row", "finding deleted")}
  return ${findingJson("v_row")};
end;
$$;
${userGrant(`${fn("delete_inspection_finding")}(uuid)`)}
${raiseCase(q)}`;
}
