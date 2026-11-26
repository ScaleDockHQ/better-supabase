import type { BlockSqlContext } from "../context.ts";

import { SERVICE_CALLER, userGrant } from "../shared.ts";

/** What `archiveFunctions` takes from the scores module's builders. */
export interface ScoreArchiveParts {
  readonly models: string;
  readonly m: (column: string) => string;
  readonly fn: (name: string) => string;
  readonly manage: string;
  readonly modelJson: (row: string) => string;
  readonly modelRecord: (type: string, row: string, summary: string) => string;
  readonly modelMissing: string;
  readonly forbidden: (message: string) => string;
}

/**
 * `archive_score_model` and `restore_score_model`, when the models table has
 * the `archivedAt` column. Archiving hides the model from the lists, the
 * subject's current scores and `top_scores`, and refuses `compute_score` and
 * `upsert_score_model`; the versions and every score stay.
 */
export function archiveFunctions(
  ctx: BlockSqlContext,
  parts: ScoreArchiveParts,
): string {
  const {
    models,
    m,
    fn,
    manage,
    modelJson,
    modelRecord,
    modelMissing,
    forbidden,
  } = parts;

  if (!ctx.has("models", "archivedAt")) {
    return "";
  }

  return ["archive", "restore"]
    .map((verb) => {
      const name = `${verb}_score_model`;
      const past = verb === "archive" ? "archived" : "restored";

      return `
-- ${verb === "archive" ? "Archives a score model: it leaves the lists, subject_scores and top_scores, and compute_score refuses it. Its versions and scores stay." : "Restores an archived score model; it keeps its enabled flag."} Needs scores.manage; ${verb === "archive" ? "archiving an archived model" : "restoring one that is not archived"} returns it unchanged.
create or replace function ${fn(name)}(model_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${models};
begin
  select * into v_row from ${models} x where x.${m("id")} = ${name}.model_id for update;
  if not found then
    ${modelMissing}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${m("tenant")}`, manage)}) then
    ${forbidden("not allowed to manage score models")}
  end if;
  if (v_row.${m("archivedAt")} is not null) = ${verb === "archive" ? "true" : "false"} then
    return ${modelJson("v_row")};
  end if;
  update ${models} x set ${m("archivedAt")} = ${verb === "archive" ? "now()" : "null"}${ctx.has("models", "updatedAt") ? `, ${m("updatedAt")} = now()` : ""}
  where x.${m("id")} = v_row.${m("id")}
  returning * into v_row;
  ${modelRecord(`score_model.${past}`, "v_row", `${past} score model`)}
  return ${modelJson("v_row")};
end;
$$;
${userGrant(`${fn(name)}(uuid)`)}
`;
    })
    .join("");
}
