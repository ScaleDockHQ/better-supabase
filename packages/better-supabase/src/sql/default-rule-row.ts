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

const AUTOMATION_KEY = /^[a-z][a-z0-9_-]*\.[a-z][a-z0-9_]*$/;

function keysOf(rules: BlockSqlContext, name: "enable" | "disable"): string[] {
  const keys = [...rules.list(name, [])];
  const invalid = keys.find((key) => !AUTOMATION_KEY.test(key));

  if (invalid !== undefined) {
    throw new TypeError(
      `blocks.automations.options.${name} holds "${invalid}", which is no default automation key such as "quotes.quote_to_order"`,
    );
  }

  return keys;
}

/**
 * Whether a block's default automation ships turned on: the automations
 * module's `disable` option wins over `enable`, and both win over the block's
 * own `enabled`.
 */
export function shipsEnabled(
  rules: BlockSqlContext,
  spec: DefaultAutomation,
): boolean {
  if (keysOf(rules, "disable").includes(spec.key)) {
    return false;
  }

  return keysOf(rules, "enable").includes(spec.key) || spec.enabled !== false;
}

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
