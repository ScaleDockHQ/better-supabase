import type { BlockSqlContext } from "./context.ts";
import type { Subject } from "./subjects.ts";

import { sqlString } from "../core/template.ts";

/**
 * Whether the caller holds the `write` key a registered subject type names
 * (`config.subjects.<type>.permissions.write`) in `tenant`. `true` for types
 * without one, so a module's own check decides.
 */
export function subjectWritable(
  ctx: BlockSqlContext,
  subjects: readonly (readonly [string, Subject])[],
  args: { readonly type: string; readonly tenant: string },
): string {
  const whens = subjects.flatMap(([type]) => {
    const key = ctx.subjects[type]?.permissions?.["write"];

    return key === undefined
      ? []
      : [
          `    when ${sqlString(type)} then ${ctx.can("tenant", args.tenant, sqlString(key))}`,
        ];
  });

  if (whens.length === 0) {
    return "true";
  }

  return `case ${args.type}\n${whens.join("\n")}\n    else true\n  end`;
}
