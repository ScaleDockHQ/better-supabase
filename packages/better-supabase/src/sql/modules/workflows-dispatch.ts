import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { serviceGrant } from "../shared.ts";
import { asText } from "./over-app.ts";
import { PENDING_EXTERNAL_PREFIX } from "./workflows-record.ts";

/**
 * The functions that start a run once: they lease a queued run that has no
 * engine run yet, then record its engine run. Empty without the columns.
 */
export function dispatchSql(
  ctx: BlockSqlContext,
  runJson: (alias: string) => string,
): string {
  if (!ctx.has("runs", "idempotencyKey") || !ctx.has("runs", "dispatchUntil")) {
    return "";
  }

  const fn = (name: string): string => ctx.fn(name);
  const r = ctx.table("runs");
  const cr = (column: string): string => ctx.col("runs", column);

  return `-- Leases a queued run that has no engine run yet (its external_id starts with
-- ${PENDING_EXTERNAL_PREFIX}) to the caller for lease seconds, and returns it; null when the
-- run is gone, already has an engine run, or another caller holds the lease.
-- A lease that runs out can be claimed again.
create or replace function ${fn("claim_workflow_run_dispatch")}(run uuid, lease integer default 60)
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${r}%rowtype;
begin
  update ${r} x set ${cr("dispatchUntil")} = now() + make_interval(secs => greatest(coalesce(lease, 60), 1)), ${cr("updatedAt")} = now()
  where x.${cr("id")} = run
    and ${asText(ctx, "runs", `x.${cr("status")}`)} = 'queued'
    and starts_with(x.${cr("externalId")}, ${sqlString(PENDING_EXTERNAL_PREFIX)})
    and (x.${cr("dispatchUntil")} is null or x.${cr("dispatchUntil")} < now())
  returning * into v_row;
  if not found then
    return null;
  end if;
  return ${runJson("v_row")};
end;
$$;
${serviceGrant(`${fn("claim_workflow_run_dispatch")}(uuid, integer)`)}

-- Records the engine run of a queued run and ends its lease. When the engine's
-- own report already created a row for (engine, external_id), that row keeps
-- its id and takes the key and the queued run's attributes, and the queued row
-- is deleted. Returns the run, or null when there is none.
create or replace function ${fn("set_workflow_run_engine")}(run uuid, engine text, external_id text)
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${r}%rowtype;
  v_other ${r}%rowtype;
begin
  select * into v_row from ${r} x where x.${cr("id")} = run for update;
  if not found then
    return null;
  end if;
  select * into v_other from ${r} x
  where x.${cr("engine")} = engine and x.${cr("externalId")} = external_id and x.${cr("id")} <> run
  for update;
  if found then
    delete from ${r} x where x.${cr("id")} = run;
    update ${r} x set ${cr("idempotencyKey")} = coalesce(x.${cr("idempotencyKey")}, v_row.${cr("idempotencyKey")}),
      ${cr("attributes")} = v_row.${cr("attributes")} || x.${cr("attributes")},
      ${cr("tenant")} = coalesce(x.${cr("tenant")}, v_row.${cr("tenant")}),
      ${cr("actor")} = coalesce(x.${cr("actor")}, v_row.${cr("actor")}),
      ${cr("updatedAt")} = now()
    where x.${cr("id")} = v_other.${cr("id")}
    returning * into v_row;
    return ${runJson("v_row")};
  end if;
  update ${r} x set ${cr("engine")} = engine, ${cr("externalId")} = external_id, ${cr("dispatchUntil")} = null, ${cr("updatedAt")} = now()
  where x.${cr("id")} = run
  returning * into v_row;
  return ${runJson("v_row")};
end;
$$;
${serviceGrant(`${fn("set_workflow_run_engine")}(uuid, text, text)`)}
`;
}
