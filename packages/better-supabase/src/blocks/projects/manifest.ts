import type { BlockContext } from "../create-blocks.ts";
import type { BlockOf, CompositeOptions } from "../define-block.ts";

import { approvalsBlock } from "../approvals/manifest.ts";
import { billableTimeBlock } from "../billable-time/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { invoicesBlock } from "../invoices/manifest.ts";
import { meetingsBlock } from "../meetings/manifest.ts";
import { tasksBlock } from "../tasks/manifest.ts";
import { timeTrackingBlock } from "../time-tracking/manifest.ts";

/** The blocks `projects` is made of, by block name. */
export const projectsParts: {
  readonly tasks: typeof tasksBlock;
  readonly "time-tracking": typeof timeTrackingBlock;
  readonly "billable-time": typeof billableTimeBlock;
  readonly approvals: typeof approvalsBlock;
  readonly invoices: typeof invoicesBlock;
  readonly meetings: typeof meetingsBlock;
} = {
  tasks: tasksBlock,
  "time-tracking": timeTrackingBlock,
  "billable-time": billableTimeBlock,
  approvals: approvalsBlock,
  invoices: invoicesBlock,
  meetings: meetingsBlock,
};

export type ProjectsParts = typeof projectsParts;

/**
 * The `projects` composite (ADR 0177): tasks, time tracking, billable time,
 * approvals, invoices and meetings. It installs its parts and sets their
 * defaults; the parts stay ordinary blocks in the config.
 */
export const projectsBlock: BlockOf<
  "projects",
  (options: BlockContext & CompositeOptions<ProjectsParts>) => undefined
> = defineBlock({
  name: "projects",
  composes: projectsParts,
  category: "work",
});
