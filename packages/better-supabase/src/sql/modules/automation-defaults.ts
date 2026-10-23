import type { DefaultAutomation } from "../../core/automation.ts";
import type { BlockSqlContext } from "../context.ts";

/** The block whose records a shipped automation's actions create. */
export interface AutomationTarget {
  readonly module: string;
  /** The entity's default singular name, such as `work_item`. */
  readonly singular: string;
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

  const targetType = ctx.of(target.module).naming.rename(target.singular);

  return ctx.automation({
    ...spec,
    actions: spec.actions.map((action) => ({
      ...action,
      config: { ...action.config, targetType },
    })),
  });
}
