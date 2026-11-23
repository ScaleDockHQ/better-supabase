import type { PipelineBinding } from "./pipelines-bindings.ts";

import { sqlString } from "../../core/template.ts";
import { declaredRank } from "../declared-defaults.ts";

/** The `declared_defaults` subject of a binding's stages, as a string literal. */
export function stageSubject(binding: PipelineBinding): string {
  return sqlString(binding.type);
}

/**
 * The stages the app declared as `pipeline_stage` rows, as a derived table
 * `x(key, name, category, outcome, probability, rank, color, icon)`: the same
 * shape the template's `values` list has. `source` is a jsonb list expression;
 * the outcome follows from the category the binding names.
 */
export function declaredStageTable(
  binding: PipelineBinding,
  source: string,
): string {
  const outcome = Object.entries(binding.categories)
    .map(
      ([category, result]) =>
        `when ${sqlString(category)} then ${sqlString(result)}`,
    )
    .join(" ");

  return `(select d.key, d.name, d.category, case d.category ${outcome} else 'open' end as outcome, d.probability, ${declaredRank("d.ord")} as rank, d.color, d.icon
      from rows from (jsonb_to_recordset(${source}) as (key text, name text, category text, probability smallint, color text, icon text)) with ordinality as d(key, name, category, probability, color, icon, ord)
      ) x(key, name, category, outcome, probability, rank, color, icon)`;
}
