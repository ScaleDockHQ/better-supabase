import type { DefaultAutomation } from "../../core/automation.ts";
import type { BlockSqlContext } from "../context.ts";

import { entityType } from "../resolved-names.ts";

/** The block whose records a shipped automation's actions create. */
export interface AutomationTarget {
  readonly module: string;
  /** The entity's key, such as `task`. */
  readonly entity: string;
}

/**
 * Row SQL for a default automation whose actions create records of `target`:
 * each action's config gets `targetType`, the target's record type after its
 * entity renames.
 */
export function shippedAutomation(
  ctx: BlockSqlContext,
  spec: DefaultAutomation,
  target: AutomationTarget,
): string {
  if (ctx.mode === "custom" || !ctx.installed(target.module)) {
    return "";
  }

  const targetType = entityType(ctx.of(target.module).resolved, target.entity);

  return ctx.automation({
    ...spec,
    actions: spec.actions.map((action) => ({
      ...action,
      config: { ...action.config, targetType },
    })),
  });
}
