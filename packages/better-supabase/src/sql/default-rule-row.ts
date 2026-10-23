import type { DefaultAutomation } from "../core/automation.ts";
import type { BlockSqlContext } from "./context.ts";

import { sqlString } from "../core/template.ts";

const UPDATED = [
  "subjectType",
  "trigger",
  "name",
  "description",
  "actions",
  "enabled",
  "block",
];

/**
 * The `rule_defaults` upsert for a block's default automation, written with the
 * automations module's names. `rename` maps the block's default entity names to
 * the configured ones.
 */
export function defaultRuleRow(
  rules: BlockSqlContext,
  block: string,
  rename: (name: string) => string,
  spec: DefaultAutomation,
): string {
  const d = (column: string): string => rules.col("defaults", column);

  const values = [
    sqlString(spec.key),
    sqlString(block),
    sqlString(rename(spec.subjectType)),
    sqlString(rename(spec.trigger)),
    sqlString(spec.name),
    spec.description === undefined ? "null" : sqlString(spec.description),
    `${sqlString(JSON.stringify(spec.actions))}::jsonb`,
    spec.enabled === false ? "false" : "true",
  ];

  return `insert into ${rules.table("defaults")} (${d("key")}, ${d("block")}, ${d("subjectType")}, ${d("trigger")}, ${d("name")}, ${d("description")}, ${d("actions")}, ${d("enabled")})
values (${values.join(", ")})
on conflict (${d("key")}) do update set ${UPDATED.map((column) => `${d(column)} = excluded.${d(column)}`).join(", ")}, ${d("updatedAt")} = now();`;
}
