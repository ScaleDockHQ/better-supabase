"use server";

import type { ListQueryInput } from "better-supabase/list";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

import {
  TASK_LIST,
  TASK_SUBJECT,
  TASK_VIEWS,
  TaskStatusSchema,
} from "./project-types";

const Id = v.pipe(v.string(), v.uuid());

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
export const createProject = bs.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
    }),
    requireTenant: true,
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
 * Creates a task from the record form. The table's policies keep the row in
 * the caller's organization, and the composite foreign key keeps the project
 * in it too.
 */
export const createTask = bs.action(
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
    requireTenant: true,
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
 * Moves a task between two cards, into a status column. `rank.move` writes
 * the status and the new key in one statement, as the caller.
 */
export const moveTask = bs.action(
  {
    input: v.object({
      id: Id,
      status: TaskStatusSchema,
      previousId: v.nullable(Id),
      nextId: v.nullable(Id),
    }),
    requireTenant: true,
  },
  async ({ id, status, previousId, nextId }, { supabase, auth }) => {
    const moved = await blocks(supabase).rank.move(TASK_SUBJECT, id, {
      previous: previousId,
      next: nextId,
      group: status,
    });

    refreshCaller(auth);

    return moved;
  },
);

/** Sets the status of the selected tasks, or deletes them, in one statement. */
export const runTaskBulkAction = bs.action(
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
    requireTenant: true,
  },
  async (input, { db, auth }) => {
    const where = { id: { in: input.ids } };

    const changed =
      input.kind === "status"
        ? await db.tasks.updateMany({ where, data: { status: input.status } })
        : await db.tasks.deleteMany({ where });

    if (!changed.ok) {
      return changed;
    }

    refreshCaller(auth);

    return ok(changed.data);
  },
);

type TaskViewQuery = {
  -readonly [
    K in keyof ListQueryInput<string, "status" | "project">
  ]: ListQueryInput<string, "status" | "project">[K];
};

/** Saves the current screen, search and filters as a named view. */
export const saveTaskView = bs.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(80)),
      view: v.picklist(TASK_VIEWS),
      q: v.pipe(v.string(), v.trim(), v.maxLength(200)),
      status: v.nullable(TaskStatusSchema),
      projectId: v.nullable(Id),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "views.read"),
  },
  async ({ name, view, q, status, projectId }, { tenant, supabase, auth }) => {
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

    const saved = await blocks(supabase).savedViews.save({
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

export const deleteTaskView = bs.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "views.read"),
  },
  async ({ id }, { supabase, auth }) => {
    const deleted = await blocks(supabase).savedViews.delete(id);

    if (!deleted.ok) {
      return deleted;
    }

    refreshCaller(auth);

    return ok(deleted.data);
  },
);

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function retryProjects() {
  refresh();
}
