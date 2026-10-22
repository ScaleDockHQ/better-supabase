"use server";

import type { WorkItemChange } from "better-supabase/blocks/work-items";
import type { ListQueryInput } from "better-supabase/list";

import { dbError, err, ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

import type { WorkItemSort } from "./work-types";

import {
  WORK_ITEM_LIST,
  WORK_ITEM_SUBJECT,
  WorkItemSortSchema,
  WorkItemStateSchema,
} from "./work-types";

/** The saved view query, built field by field. */
type WorkViewQuery = {
  -readonly [K in keyof ListQueryInput<WorkItemSort, "state">]: ListQueryInput<
    WorkItemSort,
    "state"
  >[K];
};

const Id = v.pipe(v.string(), v.uuid());
const OptionalId = v.nullish(Id);

/** Applies one batch of item changes; a rejected change becomes the error. */
async function applyChanges(
  supabase: Parameters<typeof blocks>[0],
  changes: readonly WorkItemChange[],
) {
  const result = await blocks(supabase).workItems.update(changes);

  if (!result.ok) {
    return result;
  }

  const [rejected] = result.data.rejected;

  if (rejected) {
    return err(
      rejected.hint === undefined
        ? dbError("raised", rejected.reason)
        : dbError("raised", rejected.reason, { hint: rejected.hint }),
    );
  }

  return ok(result.data.accepted.length);
}

/**
 * Creates a work item and sets the tenant's custom fields on it. Without a
 * pipeline the work-items module puts it on the organization's default one,
 * which it seeds on first use.
 */
export const createWorkItem = bs.action(
  {
    input: v.object({
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      teamId: v.optional(v.union([v.literal(""), Id]), ""),
      priority: v.optional(
        v.pipe(v.number(), v.integer(), v.minValue(0), v.maxValue(4)),
        0,
      ),
      custom: v.optional(v.record(v.string(), v.string()), {}),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "work_items.write"),
  },
  async ({ title, teamId, priority, custom }, { tenant, supabase, auth }) => {
    const client = blocks(supabase, tenant);

    const created = await client.workItems.create(
      tenant,
      teamId === "" ? { title, priority } : { title, priority, teamId },
    );

    if (!created.ok) {
      return created;
    }

    const values = Object.entries(custom);

    if (values.length > 0) {
      const definitions =
        await client.customFields.listDefinitions(WORK_ITEM_SUBJECT);

      if (!definitions.ok) {
        return definitions;
      }

      const idOf = new Map(
        definitions.data.map((definition) => [definition.key, definition.id]),
      );

      const subject = { type: WORK_ITEM_SUBJECT, id: created.data.id };

      const saved = await Promise.all(
        values.flatMap(([key, value]) => {
          const id = idOf.get(key);

          return id === undefined
            ? []
            : [client.customFields.setValue(subject, id, value)];
        }),
      );

      const failed = saved.find((result) => !result.ok);

      if (failed) {
        return failed;
      }
    }

    refreshCaller(auth);

    return ok(created.data.identifier);
  },
);

/**
 * A drag on the board. A change of column sets the item's stage, which the
 * pipelines trigger checks against the allowed transitions; the position then
 * goes through the rank block, between the cards it landed between. `ordered:
 * false` means the stage changed but the position wasn't saved.
 */
export const moveWorkItem = bs.action(
  {
    input: v.object({
      id: Id,
      stageId: Id,
      stageChanged: v.boolean(),
      previousId: OptionalId,
      nextId: OptionalId,
    }),
    requireTenant: true,
    authorize: (session) => can(session, "work_items.write"),
  },
  async (
    { id, stageId, stageChanged, previousId, nextId },
    { supabase, auth },
  ) => {
    if (stageChanged) {
      const moved = await applyChanges(supabase, [
        { workItemId: id, field: "stageId", value: stageId },
      ]);

      if (!moved.ok) {
        return moved;
      }
    }

    const ranked = await blocks(supabase).rank.move(WORK_ITEM_SUBJECT, id, {
      previous: previousId ?? null,
      next: nextId ?? null,
    });

    refreshCaller(auth);

    if (!ranked.ok) {
      return stageChanged ? ok({ ordered: false }) : ranked;
    }

    return ok({ ordered: true });
  },
);

/** An inline edit of the grid's status column. */
export const setWorkItemStage = bs.action(
  {
    input: v.object({ id: Id, stageId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "work_items.write"),
  },
  async ({ id, stageId }, { supabase, auth }) => {
    const moved = await applyChanges(supabase, [
      { workItemId: id, field: "stageId", value: stageId },
    ]);

    if (!moved.ok) {
      return moved;
    }

    refreshCaller(auth);

    return ok(true);
  },
);

/** An inline edit of the grid's assignee column; `null` unassigns. */
export const setWorkItemAssignee = bs.action(
  {
    input: v.object({ id: Id, userId: OptionalId }),
    requireTenant: true,
    authorize: (session) => can(session, "work_items.write"),
  },
  async ({ id, userId }, { supabase, auth }) => {
    const assigned = await blocks(supabase).workItems.assign(
      id,
      userId ? [userId] : [],
    );

    if (!assigned.ok) {
      return assigned;
    }

    refreshCaller(auth);

    return ok(assigned.data);
  },
);

/** Creates a team, from the team picker's empty state. */
export const createTeam = bs.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(80)),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "teams.manage"),
  },
  async ({ name }, { tenant, supabase, auth }) => {
    const created = await blocks(supabase).teams.create(tenant, name);

    if (!created.ok) {
      return created;
    }

    refreshCaller(auth);

    return ok(created.data.id);
  },
);

/** Saves the grid's filters and sort as one of the caller's views. */
export const saveWorkView = bs.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(80)),
      q: v.pipe(v.string(), v.trim(), v.maxLength(200)),
      state: v.nullable(WorkItemStateSchema),
      sort: WorkItemSortSchema,
    }),
    requireTenant: true,
    authorize: (session) => can(session, "views.read"),
  },
  async ({ name, q, state, sort }, { tenant, supabase, auth }) => {
    const query: WorkViewQuery = { sort };

    if (q !== "") {
      query.q = q;
    }

    if (state !== null) {
      query.facets = { state: [state] };
    }

    const saved = await blocks(supabase).savedViews.save({
      organizationId: tenant,
      list: WORK_ITEM_LIST,
      name,
      state: { query },
    });

    if (!saved.ok) {
      return saved;
    }

    refreshCaller(auth);

    return ok(saved.data.id);
  },
);

export const deleteWorkView = bs.action(
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

/**
 * Runs one bulk action on the selected items, each row on its own, and returns
 * the per-row results so the bar can report the failures.
 */
export const runWorkBulkAction = bs.action(
  {
    input: v.variant("action", [
      v.object({
        action: v.literal("state"),
        ids: v.pipe(v.array(Id), v.minLength(1), v.maxLength(500)),
        to: WorkItemStateSchema,
      }),
      v.object({
        action: v.literal("delete"),
        ids: v.pipe(v.array(Id), v.minLength(1), v.maxLength(500)),
      }),
    ]),
    requireTenant: true,
    authorize: (session) => can(session, "bulk.run"),
  },
  async (input, { tenant, supabase, auth }) => {
    const { bulk } = blocks(supabase);

    const result =
      input.action === "state"
        ? await bulk.run({
            organizationId: tenant,
            subjectType: WORK_ITEM_SUBJECT,
            rows: input.ids,
            action: "stateMachine.transition",
            args: { to: input.to },
          })
        : await bulk.run({
            organizationId: tenant,
            subjectType: WORK_ITEM_SUBJECT,
            rows: input.ids,
            action: "trash.trash",
            args: {},
          });

    if (!result.ok) {
      return result;
    }

    refreshCaller(auth);

    return ok({
      total: result.data.total,
      succeeded: result.data.succeeded,
      failed: result.data.results.flatMap((row) =>
        row.ok
          ? []
          : [
              {
                id: row.id,
                message: row.error?.message ?? "",
                code: row.error?.code ?? null,
              },
            ],
      ),
    });
  },
);

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function retryWork() {
  refresh();
}
