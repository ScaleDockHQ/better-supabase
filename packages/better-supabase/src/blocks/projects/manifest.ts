import type { BlockOf } from "../define-block.ts";
import type { ProjectsEvents } from "./events.ts";

import { approvalsBlock } from "../approvals/manifest.ts";
import { attachmentsBlock } from "../attachments/manifest.ts";
import { billableTimeBlock } from "../billable-time/manifest.ts";
import { commentsBlock } from "../comments/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { invoicesBlock } from "../invoices/manifest.ts";
import { meetingsBlock } from "../meetings/manifest.ts";
import { relationsBlock } from "../relations/manifest.ts";
import { savedViewsBlock } from "../saved-views/manifest.ts";
import { subjectsBlock } from "../subjects/manifest.ts";
import { tagsBlock } from "../tags/manifest.ts";
import { tasksBlock } from "../tasks/manifest.ts";
import { timeEntriesBlock } from "../time-entries/manifest.ts";
import { timelineBlock } from "../timeline/manifest.ts";
import { projectsEvents } from "./events.ts";
import { createProjects } from "./projects.ts";

/** The blocks `projects` is made of, by block name. */
export const projectsParts: {
  readonly tasks: typeof tasksBlock;
  readonly "time-entries": typeof timeEntriesBlock;
  readonly "billable-time": typeof billableTimeBlock;
  readonly approvals: typeof approvalsBlock;
  readonly invoices: typeof invoicesBlock;
  readonly meetings: typeof meetingsBlock;
  readonly comments: typeof commentsBlock;
  readonly attachments: typeof attachmentsBlock;
  readonly tags: typeof tagsBlock;
  readonly timeline: typeof timelineBlock;
  readonly relations: typeof relationsBlock;
  readonly "saved-views": typeof savedViewsBlock;
  readonly subjects: typeof subjectsBlock;
} = {
  tasks: tasksBlock,
  "time-entries": timeEntriesBlock,
  "billable-time": billableTimeBlock,
  approvals: approvalsBlock,
  invoices: invoicesBlock,
  meetings: meetingsBlock,
  comments: commentsBlock,
  attachments: attachmentsBlock,
  tags: tagsBlock,
  timeline: timelineBlock,
  relations: relationsBlock,
  "saved-views": savedViewsBlock,
  subjects: subjectsBlock,
};

export type ProjectsParts = typeof projectsParts;

/**
 * The `projects` composite (ADR 0196): tasks, time tracking, billable time,
 * approvals, invoices, meetings, comments, files, tags, the timeline,
 * relations, saved views and record teams. It installs its parts and sets their
 * defaults; the parts stay ordinary blocks in the config. An existing install
 * gains the parts it did not already have on `upgrade`.
 */
export const projectsBlock: BlockOf<
  "projects",
  typeof createProjects,
  ProjectsEvents
> = defineBlock({
  name: "projects",
  sql: ["projects"],
  events: projectsEvents,
  composes: projectsParts,
  create: createProjects,
  category: "work",
  entities: {
    project: { mutability: "read-only" },
    project_update: {
      mutability: "editable",
      permissions: { read: "initiatives.read", create: "initiatives.manage" },
      emits: { create: true },
    },
    initiative: {
      mutability: "editable",
      permissions: { read: "initiatives.read", manage: "initiatives.manage" },
      emits: { create: true, update: true, archive: true, delete: true },
    },
  },
  description:
    "Tasks, time, billing, comments, files, tags, timeline, relations and saved views installed together for a project page.",
});
