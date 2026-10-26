"use server";

import type { ListQueryInput } from "better-supabase/list";

import { dbError, err, ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { projectPage } from "./project-record";
import {
  PROJECT_HISTORY_FIELDS,
  PROJECT_SUBJECT,
  TASK_LIST,
  TASK_SUBJECT,
  TASK_VIEWS,
  TaskStatusSchema,
} from "./project-types";

const Id = v.pipe(v.string(), v.uuid());

export const snapshotProjectVersions = projectPage.actions.versions.snapshot;

/** An empty form field means no value. */
const OptionalId = v.pipe(
  v.optional(v.string(), ""),
  v.transform((value) => (value === "" ? null : value)),
  v.nullable(Id),
);

const OptionalDate = v.pipe(
  v.optional(v.string(), ""),
  v.transform((value) => (value === "" ? null : value)),
  v.nullable(v.pipe(v.string(), v.isoDate())),
);

/** Creates a project; budget and currency keep their column defaults. */
export const createProject = bsb.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
    }),
    requireOrganization: true,
  },
  async ({ name }, { tenant, db, auth }) => {
    const created = await db.projects.create(
      { name, organizationId: tenant },
      { select: ["id"] },
    );

    if (!created.ok) {
      return created;
    }

    refreshCaller(auth);

    return ok(created.data.id);
  },
);

/**
 * Creates a task from the record form. The table's policies keep the row in the
 * caller's organization, and the composite foreign key keeps the project in it
 * too.
 */
export const createTask = bsb.action(
  {
    input: v.pipe(
      v.object({
        title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
        status: v.optional(TaskStatusSchema, "todo"),
        projectId: Id,
        assigneeId: OptionalId,
        startsOn: OptionalDate,
        dueOn: OptionalDate,
      }),
      v.check(
        (task) =>
          task.startsOn === null ||
          task.dueOn === null ||
          task.startsOn <= task.dueOn,
        "The start date is after the due date.",
      ),
    ),
    requireOrganization: true,
  },
  async (task, { tenant, db, auth }) => {
    const created = await db.tasks.create(
      { ...task, organizationId: tenant },
      { select: ["id"] },
    );

    if (!created.ok) {
      return created;
    }

    refreshCaller(auth);

    return ok(created.data.id);
  },
);

/**
 * Moves a task between two cards, into a status column. `rank.move` writes the
 * status and the new key in one statement, as the caller.
 */
export const moveTask = bsb.action(
  {
    input: v.object({
      id: Id,
      status: TaskStatusSchema,
      previousId: v.nullable(Id),
      nextId: v.nullable(Id),
    }),
    requireOrganization: true,
  },
  async ({ id, status, previousId, nextId }, { db, auth }) => {
    const moved = await db.rank.move(TASK_SUBJECT, id, {
      previous: previousId,
      next: nextId,
      group: status,
    });

    refreshCaller(auth);

    return moved;
  },
);

/** Sets the status of the selected tasks, or deletes them, in one statement. */
export const runTaskBulkAction = bsb.action(
  {
    input: v.variant("kind", [
      v.object({
        kind: v.literal("status"),
        ids: v.pipe(v.array(Id), v.minLength(1), v.maxLength(500)),
        status: TaskStatusSchema,
      }),
      v.object({
        kind: v.literal("delete"),
        ids: v.pipe(v.array(Id), v.minLength(1), v.maxLength(500)),
      }),
    ]),
    requireOrganization: true,
  },
  async (input, { db, auth }) => {
    const where = { id: { in: input.ids } };

    const changed =
      input.kind === "status"
        ? await db.tasks.update({ where }, { status: input.status })
        : await db.tasks.delete({ where });

    if (!changed.ok) {
      return changed;
    }

    refreshCaller(auth);

    return ok(changed.data);
  },
);

/**
 * Sets one field on the selected tasks. Each row runs as the caller, so the
 * policies and column grants decide what changes, and a failing row leaves the
 * others.
 */
export const setTaskField = bsb.action(
  {
    input: v.object({
      ids: v.pipe(v.array(Id), v.minLength(1), v.maxLength(500)),
      values: v.union([
        v.object({ due_on: v.nullable(v.pipe(v.string(), v.isoDate())) }),
        v.object({ assignee_id: v.nullable(Id) }),
      ]),
    }),
    requireOrganization: true,
    authorize: async () => can(await getPermissions(), "bulk.run"),
  },
  async ({ ids, values }, { db, auth }) => {
    const patch =
      "due_on" in values
        ? { dueOn: values.due_on }
        : { assigneeId: values.assignee_id };

    const results = await Promise.all(
      ids.map((id) => db.tasks.update(id, patch)),
    );

    refreshCaller(auth);

    return ok(results.filter((result) => result.ok).length);
  },
);

type TaskViewQuery = {
  -readonly [
    K in keyof ListQueryInput<string, "status" | "project">
  ]: ListQueryInput<string, "status" | "project">[K];
};

/** Saves the current screen, search and filters as a named view. */
export const saveTaskView = bsb.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(80)),
      view: v.picklist(TASK_VIEWS),
      q: v.pipe(v.string(), v.trim(), v.maxLength(200)),
      status: v.nullable(TaskStatusSchema),
      projectId: v.nullable(Id),
    }),
    requireOrganization: true,
    authorize: async () => can(await getPermissions(), "views.read"),
  },
  async ({ name, view, q, status, projectId }, { tenant, db, auth }) => {
    const query: TaskViewQuery = {};
    const facets: Record<string, string[]> = {};

    if (q !== "") {
      query.q = q;
    }

    if (status !== null) {
      facets["status"] = [status];
    }

    if (projectId !== null) {
      facets["project"] = [projectId];
    }

    if (Object.keys(facets).length > 0) {
      query.facets = facets;
    }

    const saved = await db.$blocks.savedViews.upsert({
      organizationId: tenant,
      list: TASK_LIST,
      name,
      kind: view,
      state: { query },
    });

    if (!saved.ok) {
      return saved;
    }

    refreshCaller(auth);

    return ok(saved.data.id);
  },
);

export const deleteTaskView = bsb.action(
  {
    input: v.object({ id: Id }),
    requireOrganization: true,
    authorize: async () => can(await getPermissions(), "views.read"),
  },
  async ({ id }, { db, auth }) => {
    const deleted = await db.$blocks.savedViews.delete(id);

    if (!deleted.ok) {
      return deleted;
    }

    refreshCaller(auth);

    return ok(deleted.data);
  },
);

/**
 * Writes the chosen fields of a version back to the project and leaves the rest
 * as they are (`versions.restoreFields`). The snapshot trigger already kept the
 * current values, so the restore can be undone from the history.
 */
export const restoreProjectFields = bsb.action(
  {
    input: v.object({
      projectId: Id,
      versionId: Id,
      fields: v.pipe(
        v.array(v.picklist(PROJECT_HISTORY_FIELDS)),
        v.minLength(1),
      ),
    }),
    requireOrganization: true,
    authorize: async () => can(await getPermissions(), "versions.restore"),
  },
  async ({ projectId, versionId, fields }, { db, auth }) => {
    const { versions } = db;
    const version = await versions.get(versionId);

    if (!version.ok) {
      return version;
    }

    if (
      version.data.subject.type !== PROJECT_SUBJECT ||
      version.data.subject.id !== projectId
    ) {
      return err(
        dbError("not_found", "This version belongs to another record"),
      );
    }

    const restored = await versions.restoreFields(versionId, fields);

    if (!restored.ok) {
      return restored;
    }

    refreshCaller(auth);

    return ok(null);
  },
);

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function retryProjects() {
  refresh();
}
