import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What the task `page`, `facets` and `count` accept (ADR 0749, 1077). The
 * manifest declares the same names, and the SQL list function `page_tasks`
 * implements them. `number` is the default, newest first. `ready` and `waiting`
 * split the open tasks by their `waiting_on` count.
 */
export const taskListSurface: EntityListSurface = {
  sorts: ["number", "title", "dueAt", "createdAt"],
  facets: ["state", "priority"],
  filters: [
    "state",
    "priority",
    "teamId",
    "projectId",
    "iterationId",
    "parentId",
    "assigneeId",
    "open",
    "ready",
    "waiting",
    "dueFrom",
    "dueTo",
    "triage",
    "milestoneId",
  ],
  search: ["title", "identifier"],
};

/** The same for a project, over the SQL list function `page_projects`. */
export const projectListSurface: EntityListSurface = {
  sorts: ["name", "key", "createdAt"],
  facets: ["status"],
  filters: ["status", "ownerId", "archived"],
  search: ["name", "key"],
};
