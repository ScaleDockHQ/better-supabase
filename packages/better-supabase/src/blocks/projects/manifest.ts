import type { BlockOf } from "../define-block.ts";

import { approvalsBlock } from "../approvals/manifest.ts";
import { billableTimeBlock } from "../billable-time/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { invoicesBlock } from "../invoices/manifest.ts";
import { meetingsBlock } from "../meetings/manifest.ts";
import { tasksBlock } from "../tasks/manifest.ts";
import { timeEntriesBlock } from "../time-entries/manifest.ts";
import { createProjects } from "./projects.ts";

/** The blocks `projects` is made of, by block name. */
export const projectsParts: {
  readonly tasks: typeof tasksBlock;
  readonly "time-entries": typeof timeEntriesBlock;
  readonly "billable-time": typeof billableTimeBlock;
  readonly approvals: typeof approvalsBlock;
  readonly invoices: typeof invoicesBlock;
  readonly meetings: typeof meetingsBlock;
} = {
  tasks: tasksBlock,
  "time-entries": timeEntriesBlock,
  "billable-time": billableTimeBlock,
  approvals: approvalsBlock,
  invoices: invoicesBlock,
  meetings: meetingsBlock,
};

export type ProjectsParts = typeof projectsParts;

/**
 * The `projects` composite (ADR 0196): tasks, time tracking, billable time,
 * approvals, invoices and meetings. It installs its parts and sets their
 * defaults; the parts stay ordinary blocks in the config.
 */
export const projectsBlock: BlockOf<"projects", typeof createProjects> =
  defineBlock({
    name: "projects",
    composes: projectsParts,
    create: createProjects,
    category: "work",
    description:
      "Tasks, time tracking, billable time, approvals, invoices and meetings installed together for project work.",
  });
