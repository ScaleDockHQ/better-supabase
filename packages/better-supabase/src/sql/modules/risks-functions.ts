import type { BlockSqlContext } from "../context.ts";
import type { RisksSql } from "./risks-sql.ts";

import { sqlString } from "../../core/template.ts";
import { assignNumberSql } from "../numbering-sql.ts";
import { fail, serviceGrant, userGrant, writeExtraColumns } from "../shared.ts";
import { risksSql } from "./risks-sql.ts";

const matrixInvalid = (message: string): string =>
  fail("RISK_MATRIX_INVALID", message, "22023");

/** The checks save_risk_matrix runs on one axis of levels. */
function levelsCheck(arg: string, what: string): string {
  return `if jsonb_typeof(${arg}) is distinct from 'array' or jsonb_array_length(${arg}) not between 2 and 10 then
    ${matrixInvalid(`${what} must be a list of 2 to 10 levels`)}
  end if;
  if exists (
    select 1 from jsonb_array_elements(${arg}) l
    where jsonb_typeof(l) <> 'object' or jsonb_typeof(l -> 'value') is distinct from 'number'
      or (l ->> 'value') !~ '^[0-9]{1,2}$' or coalesce(length(trim(l ->> 'label')), 0) not between 1 and 100
  ) then
    ${matrixInvalid(`${what} values must be 1 to n, each once, with a label of 1 to 100 characters`)}
  end if;
  if (select array_agg((l ->> 'value')::integer order by (l ->> 'value')::integer) from jsonb_array_elements(${arg}) l)
    <> (select array_agg(g order by g) from generate_series(1, jsonb_array_length(${arg})) g) then
    ${matrixInvalid(`${what} values must be 1 to n, each once, with a label of 1 to 100 characters`)}
  end if;`;
}

/** The checks save_risk_matrix runs on the bands, against v_min and v_max. */
function bandsCheck(arg: string): string {
  const gaps = matrixInvalid(
    "bands must cover every score from the lowest to the highest without gaps or overlaps",
  );

  return `if jsonb_typeof(${arg}) is distinct from 'array' or jsonb_array_length(${arg}) not between 1 and 10 then
    ${matrixInvalid("bands must be a list of 1 to 10 bands")}
  end if;
  if exists (
    select 1 from jsonb_array_elements(${arg}) b
    where jsonb_typeof(b) <> 'object' or coalesce(b ->> 'key', '') !~ '^[a-z][a-z0-9_]{0,31}$'
      or coalesce(length(trim(b ->> 'label')), 0) not between 1 and 100
      or jsonb_typeof(b -> 'min') is distinct from 'number' or jsonb_typeof(b -> 'max') is distinct from 'number'
      or (b ->> 'min') !~ '^[0-9]{1,4}$' or (b ->> 'max') !~ '^[0-9]{1,4}$'
  ) then
    ${matrixInvalid("each band needs a key of lowercase letters, digits and underscores, a label, and whole-number min and max")}
  end if;
  if (select count(distinct b ->> 'key') from jsonb_array_elements(${arg}) b) <> jsonb_array_length(${arg}) then
    ${matrixInvalid("band keys must be unique")}
  end if;
  if exists (
    select 1 from (
      select (b ->> 'min')::integer as lo, (b ->> 'max')::integer as hi,
        lag((b ->> 'max')::integer) over (order by (b ->> 'min')::integer) as prev,
        row_number() over (order by (b ->> 'min')::integer) as n
      from jsonb_array_elements(${arg}) b
    ) s
    where s.lo > s.hi or (s.n = 1 and s.lo <> v_min) or (s.n > 1 and s.lo <> s.prev + 1)
  ) or (select max((b ->> 'max')::integer) from jsonb_array_elements(${arg}) b) <> v_max then
    ${gaps}
  end if;`;
}

/** Recomputes the scores and bands of the risks on matrix row `matrix`. */
function rescore(q: RisksSql, matrix: string): string {
  const { r, risks } = q;

  const side = (name: "inherent" | "residual"): string => {
    const value = q.score(
      matrix,
      `x.${r(`${name}Likelihood`)}`,
      `x.${r(`${name}Impact`)}`,
    );

    return `${r(`${name}Score`)} = case when x.${r(`${name}Likelihood`)} is null then null else ${value} end,
    ${r(`${name}Band`)} = case when x.${r(`${name}Likelihood`)} is null then null else ${q.band(matrix, value)} end`;
  };

  return `update ${risks} x set
    ${side("inherent")},
    ${side("residual")}
  where x.${r("tenant")} = ${matrix}.${q.m("tenant")} and x.${r("matrix")} = ${matrix}.${q.m("id")};`;
}

function matrixFunctions(ctx: BlockSqlContext, q: RisksSql): string {
  const { fn, m, r, matrices, risks, matrixJson } = q;
  const idType = ctx.idType;
  const d = q.defaultMatrix;

  return `
-- The organization's default matrix, seeded from options.defaultMatrix when it
-- has no matrix yet. The other functions call it; it is not an entry point.
create or replace function ${fn("ensure_risk_matrix")}(tenant ${idType})
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select x.${m("id")} into v_id from ${matrices} x
  where x.${m("tenant")} = ensure_risk_matrix.tenant
  order by x.${m("isDefault")} desc, x.${m("createdAt")}
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
  insert into ${matrices} (${m("tenant")}, ${m("key")}, ${m("name")}, ${m("likelihoodLevels")}, ${m("impactLevels")}, ${m("bands")}, ${m("scoring")}, ${m("isDefault")})
  values (
    ensure_risk_matrix.tenant, ${sqlString(d.key)}, ${sqlString(d.name)},
    ${sqlString(JSON.stringify(d.likelihoodLevels))}::jsonb,
    ${sqlString(JSON.stringify(d.impactLevels))}::jsonb,
    ${sqlString(JSON.stringify(d.bands))}::jsonb,
    ${sqlString(d.scoring)}, true
  )
  on conflict do nothing
  returning ${m("id")} into v_id;
  if v_id is null then
    select x.${m("id")} into v_id from ${matrices} x
    where x.${m("tenant")} = ensure_risk_matrix.tenant
    order by x.${m("isDefault")} desc, x.${m("createdAt")}
    limit 1;
  end if;
  return v_id;
end;
$$;
${serviceGrant(`${fn("ensure_risk_matrix")}(${idType})`)}

-- Creates a matrix or, with matrix_id, changes one. likelihood_levels and
-- impact_levels are [{ value, label }] with values 1 to n; bands are
-- [{ key, label, min, max }] covering every score once. A matrix risks use
-- keeps its level counts, and their scores and bands follow the new rules.
create or replace function ${fn("save_risk_matrix")}(tenant ${idType}, key text, name text, likelihood_levels jsonb, impact_levels jsonb, bands jsonb, scoring text default 'product', is_default boolean default false, matrix_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${matrices};
  v_old ${matrices};
  v_min integer;
  v_max integer;
  v_nl integer;
  v_ni integer;
begin
  if not ${q.allowed("save_risk_matrix.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage risk matrices")}
  end if;
  if coalesce(save_risk_matrix.key, '') !~ '^[a-z][a-z0-9_-]{0,62}$' then
    ${matrixInvalid("key must be lowercase letters, digits, dashes and underscores")}
  end if;
  if coalesce(length(trim(save_risk_matrix.name)), 0) not between 1 and 200 then
    ${matrixInvalid("name must be 1 to 200 characters")}
  end if;
  if coalesce(save_risk_matrix.scoring, '') not in ('product', 'sum') then
    ${matrixInvalid("scoring must be product or sum")}
  end if;
  ${levelsCheck("save_risk_matrix.likelihood_levels", "likelihood_levels")}
  ${levelsCheck("save_risk_matrix.impact_levels", "impact_levels")}
  v_nl := jsonb_array_length(save_risk_matrix.likelihood_levels);
  v_ni := jsonb_array_length(save_risk_matrix.impact_levels);
  v_min := case when save_risk_matrix.scoring = 'sum' then 2 else 1 end;
  v_max := case when save_risk_matrix.scoring = 'sum' then v_nl + v_ni else v_nl * v_ni end;
  ${bandsCheck("save_risk_matrix.bands")}
  if save_risk_matrix.matrix_id is not null then
    select * into v_old from ${matrices} x
    where x.${m("id")} = save_risk_matrix.matrix_id and x.${m("tenant")} = save_risk_matrix.tenant
    for update;
    if not found then
      ${q.matrixMissing}
    end if;
    if (jsonb_array_length(v_old.${m("likelihoodLevels")}) <> v_nl or jsonb_array_length(v_old.${m("impactLevels")}) <> v_ni)
      and exists (select 1 from ${risks} y where y.${r("tenant")} = v_old.${m("tenant")} and y.${r("matrix")} = v_old.${m("id")}) then
      ${fail("RISK_MATRIX_IN_USE", "risks use this matrix, so its level counts can't change", "55000")}
    end if;
  end if;
  if save_risk_matrix.is_default then
    update ${matrices} x set ${m("isDefault")} = false, ${m("updatedAt")} = now()
    where x.${m("tenant")} = save_risk_matrix.tenant and x.${m("isDefault")}
      and x.${m("id")} is distinct from save_risk_matrix.matrix_id;
  end if;
  if v_old.${m("id")} is null then
    insert into ${matrices} (${m("tenant")}, ${m("key")}, ${m("name")}, ${m("likelihoodLevels")}, ${m("impactLevels")}, ${m("bands")}, ${m("scoring")}, ${m("isDefault")})
    values (save_risk_matrix.tenant, save_risk_matrix.key, trim(save_risk_matrix.name), save_risk_matrix.likelihood_levels, save_risk_matrix.impact_levels, save_risk_matrix.bands, save_risk_matrix.scoring,
      save_risk_matrix.is_default or not exists (select 1 from ${matrices} y where y.${m("tenant")} = save_risk_matrix.tenant and y.${m("isDefault")}))
    returning * into v_row;
    ${q.recordMatrix("risk_matrix.created", "v_row", "risk matrix created")}
  else
    update ${matrices} x set
      ${m("key")} = save_risk_matrix.key,
      ${m("name")} = trim(save_risk_matrix.name),
      ${m("likelihoodLevels")} = save_risk_matrix.likelihood_levels,
      ${m("impactLevels")} = save_risk_matrix.impact_levels,
      ${m("bands")} = save_risk_matrix.bands,
      ${m("scoring")} = save_risk_matrix.scoring,
      -- The default stays the default until another matrix takes over.
      ${m("isDefault")} = x.${m("isDefault")} or save_risk_matrix.is_default,
      ${m("updatedAt")} = now()
    where x.${m("id")} = v_old.${m("id")}
    returning * into v_row;
    ${rescore(q, "v_row")}
    ${q.recordMatrix("risk_matrix.updated", "v_row", "risk matrix updated")}
  end if;
  return ${matrixJson("v_row")};
exception when unique_violation then
  ${matrixInvalid("another matrix of this organization has this key")}
end;
$$;
${userGrant(`${fn("save_risk_matrix")}(${idType}, text, text, jsonb, jsonb, jsonb, text, boolean, uuid)`)}

-- The organization's matrices, the default first. Seeds the default matrix
-- the first time.
create or replace function ${fn("list_risk_matrices")}(tenant ${idType})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not ${q.allowed("list_risk_matrices.tenant", q.read)} then
    ${q.forbidden("not allowed to read risks")}
  end if;
  perform ${fn("ensure_risk_matrix")}(list_risk_matrices.tenant);
  return coalesce((
    select jsonb_agg(${matrixJson("x")} order by x.${m("isDefault")} desc, x.${m("name")})
    from ${matrices} x where x.${m("tenant")} = list_risk_matrices.tenant
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_risk_matrices")}(${idType})`)}
`;
}

function riskWrites(ctx: BlockSqlContext, q: RisksSql): string {
  const { fn, m, r, risks, matrices, has, extras, riskJson } = q;
  const idType = ctx.idType;

  const optionalText = (
    column: string,
    key: string,
    source: string,
    max: number,
  ): string =>
    has("risks", column)
      ? `
  if length(${source} ->> '${key}') > ${String(max)} then
    ${q.invalid(`${key} is at most ${String(max)} characters`)}
  end if;`
      : `
  if nullif(trim(${source} ->> '${key}'), '') is not null then
    ${q.invalid(`the risks table has no ${column} column`)}
  end if;`;

  const textChecks = (source: string): string =>
    `${optionalText("description", "description", source, 10_000)}${optionalText("cause", "cause", source, 4000)}${optionalText("consequence", "consequence", source, 4000)}
  if ${source} ? 'reviewIntervalMonths' and ${source} ->> 'reviewIntervalMonths' is not null
    and ((${source} ->> 'reviewIntervalMonths') !~ '^[0-9]{1,3}$' or (${source} ->> 'reviewIntervalMonths')::integer not between 1 and 120) then
    ${q.invalid("reviewIntervalMonths is a whole number from 1 to 120")}
  end if;
  if ${source} ? 'fields' and jsonb_typeof(${source} -> 'fields') not in ('object', 'null') then
    ${q.invalid("fields must be an object")}
  end if;`;

  const categoryCheck = `if v_category is null or not (v_category = any (${q.categories})) then
    ${fail("RISK_CATEGORY_UNKNOWN", "the category is not one of options.categories", "22023")}
  end if;`;

  const matrixCheck = (tenant: string): string => `if not exists (
    select 1 from ${matrices} x where x.${m("id")} = v_matrix and x.${m("tenant")} = ${tenant}
  ) then
    ${q.matrixMissing}
  end if;`;

  const optCols = (["description", "cause", "consequence"] as const).filter(
    (column) => has("risks", column),
  );

  const insertCols = optCols.map((column) => `, ${r(column)}`).join("");

  const insertValues = optCols
    .map((column) => `, nullif(trim(create_risk.input ->> '${column}'), '')`)
    .join("");

  const updateCols = optCols
    .map(
      (column) =>
        `\n    ${r(column)} = case when update_risk.changes ? '${column}' then nullif(trim(update_risk.changes ->> '${column}'), '') else x.${r(column)} end,`,
    )
    .join("");

  const numberAssign = assignNumberSql(
    ctx,
    ctx.resolved.entityNaming.rename("risk"),
    "create_risk.tenant",
    { seq: "v_seq", identifier: "v_number" },
    { table: risks, seq: r("sequence"), tenant: r("tenant"), prefix: "RSK-" },
  );

  return `
-- A risk the caller writes: input is { title, description, category, cause,
-- consequence, ownerId, matrixId, reviewIntervalMonths, fields }. It starts
-- identified, on the organization's default matrix without matrixId.
create or replace function ${fn("create_risk")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${risks};
  v_title text := trim(create_risk.input ->> 'title');
  v_category text := create_risk.input ->> 'category';
  v_matrix uuid;
  v_seq bigint;
  v_number text;
begin
  if not ${q.allowed("create_risk.tenant", q.write)} then
    ${q.forbidden("not allowed to write risks")}
  end if;
  if jsonb_typeof(create_risk.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    ${q.invalid("a risk needs a title of 1 to 300 characters")}
  end if;
  ${categoryCheck}${textChecks("create_risk.input")}
  v_matrix := coalesce(nullif(create_risk.input ->> 'matrixId', '')::uuid, ${fn("ensure_risk_matrix")}(create_risk.tenant));
  ${matrixCheck("create_risk.tenant")}
  ${ctx.hook("before_risk_create", [
    [idType, "create_risk.tenant"],
    ["jsonb", "create_risk.input"],
  ])}
  ${numberAssign}
  insert into ${risks} (${r("tenant")}, ${r("number")}, ${r("sequence")}, ${r("matrix")}, ${r("title")}, ${r("category")}${insertCols}, ${r("owner")}, ${r("reviewIntervalMonths")}${has("risks", "createdBy") ? `, ${r("createdBy")}` : ""})
  values (create_risk.tenant, v_number, v_seq, v_matrix, v_title, v_category${insertValues}, nullif(create_risk.input ->> 'ownerId', '')::uuid, (create_risk.input ->> 'reviewIntervalMonths')::integer${has("risks", "createdBy") ? ", auth.uid()" : ""})
  returning * into v_row;${writeExtraColumns(risks, extras, "coalesce(create_risk.input -> 'fields', '{}'::jsonb)", `x.${r("id")} = v_row.${r("id")}`, "v_row")}
  ${q.record("risk.created", "v_row", "risk created")}
  ${ctx.hook("after_risk_create", [["uuid", `v_row.${r("id")}`]])}
  return ${riskJson("v_row")};
end;
$$;
${userGrant(`${fn("create_risk")}(${idType}, jsonb)`)}

-- Changes a risk's title, description, category, cause, consequence, owner,
-- review interval, extra fields, or its matrix before the first assessment.
create or replace function ${fn("update_risk")}(risk_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${risks};
  v_title text;
  v_category text;
  v_matrix uuid;
begin
  select * into v_row from ${risks} x where x.${r("id")} = update_risk.risk_id for update;
  if not found then
    ${q.missing}
  end if;
  if not ${q.allowed(`v_row.${r("tenant")}`, q.write)} then
    ${q.forbidden("not allowed to write risks")}
  end if;
  if v_row.${r("status")} = 'closed' then
    ${q.closed}
  end if;
  if jsonb_typeof(update_risk.changes) is distinct from 'object' then
    ${q.invalid("changes must be an object")}
  end if;
  v_title := case when update_risk.changes ? 'title' then trim(update_risk.changes ->> 'title') else v_row.${r("title")} end;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    ${q.invalid("a risk needs a title of 1 to 300 characters")}
  end if;
  v_category := case when update_risk.changes ? 'category' then update_risk.changes ->> 'category' else v_row.${r("category")} end;
  ${categoryCheck}${textChecks("update_risk.changes")}
  v_matrix := v_row.${r("matrix")};
  if update_risk.changes ? 'matrixId' and (update_risk.changes ->> 'matrixId')::uuid is distinct from v_row.${r("matrix")} then
    if v_row.${r("currentAssessment")} is not null then
      ${q.invalid("a risk's matrix changes only before its first assessment")}
    end if;
    v_matrix := (update_risk.changes ->> 'matrixId')::uuid;
    ${matrixCheck(`v_row.${r("tenant")}`)}
  end if;
  update ${risks} x set
    ${r("title")} = v_title,
    ${r("category")} = v_category,${updateCols}
    ${r("owner")} = case when update_risk.changes ? 'ownerId' then nullif(update_risk.changes ->> 'ownerId', '')::uuid else x.${r("owner")} end,
    ${r("reviewIntervalMonths")} = case when update_risk.changes ? 'reviewIntervalMonths' then (update_risk.changes ->> 'reviewIntervalMonths')::integer else x.${r("reviewIntervalMonths")} end,
    ${r("matrix")} = v_matrix,
    ${r("updatedAt")} = now()
  where x.${r("id")} = v_row.${r("id")}
  returning * into v_row;${writeExtraColumns(risks, extras, "coalesce(update_risk.changes -> 'fields', '{}'::jsonb)", `x.${r("id")} = v_row.${r("id")}`, "v_row")}
  ${q.record("risk.updated", "v_row", "risk updated")}
  return ${riskJson("v_row")};
end;
$$;
${userGrant(`${fn("update_risk")}(uuid, jsonb)`)}
`;
}

export function riskFunctions(ctx: BlockSqlContext): string {
  const q = risksSql(ctx);

  return `${matrixFunctions(ctx, q)}${riskWrites(ctx, q)}`;
}
