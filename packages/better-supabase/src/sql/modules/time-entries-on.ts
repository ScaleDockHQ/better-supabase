import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail } from "../shared.ts";

const RECORD_TYPE = /^[a-z][a-z0-9_-]{0,62}$/;

/**
 * `options.on`: PL/pgSQL that refuses a subject type the option leaves out, or
 * nothing when the option is not set.
 */
export function subjectOnSql(ctx: BlockSqlContext, type: string): string {
  const types = ctx.list("on", []);

  if (types.some((item) => !RECORD_TYPE.test(item))) {
    throw new TypeError(
      "blocks.time-entries.options.on must list lowercase record types",
    );
  }

  if (types.length === 0) {
    return "";
  }

  return `
  if ${type} is not null and ${type} <> all (array[${types.map((item) => sqlString(item)).join(", ")}]::text[]) then
    ${fail("TIME_SUBJECT_INVALID", `time is tracked on ${types.join(", ")} records`, "22023")}
  end if;`;
}
