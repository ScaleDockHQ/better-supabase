import type { ModuleContext } from "../context.ts";

/** The keys the control reads return next to the extra columns. */
export const CONTROL_RESERVED = ["fields", "status"] as const;

/** The attachments module, when its table is there to reference. */
export function evidenceAttachments(
  ctx: ModuleContext,
): ModuleContext | undefined {
  return ctx.installed("attachments") && ctx.of("attachments").manages
    ? ctx.of("attachments")
    : undefined;
}
