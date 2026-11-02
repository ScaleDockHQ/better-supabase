"use server";

import { dbError, err, ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { FieldEntitySchema, FieldTypeSchema } from "./custom-fields-types";

const Id = v.pipe(v.string(), v.uuid());

/**
 * Adds a field, or relabels the entity's field with the same key. Keys are
 * lower snake case, since they name the value in the API.
 */
export const saveField = bsb.action(
  {
    input: v.object({
      entity: FieldEntitySchema,
      key: v.pipe(v.string(), v.trim(), v.regex(/^[a-z][a-z0-9_]{0,62}$/u)),
      label: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(80)),
      type: FieldTypeSchema,
      sensitive: v.optional(v.boolean(), false),
    }),
    requireTenant: true,
    permission: "custom_fields.manage",
  },
  async ({ entity, key, label, type, sensitive }, { db, auth }) => {
    const saved = await db.customFields.saveDefinition({
      entity,
      key,
      label,
      type,
      sensitive,
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth);

    return ok(saved.data.id);
  },
);

export const deleteField = bsb.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    permission: "custom_fields.manage",
  },
  async ({ id }, { db, auth }) => {
    const deleted = await db.customFields.deleteDefinition(id);

    if (!deleted.ok) {
      return deleted;
    }

    await refreshCaller(auth);

    return ok(deleted.data);
  },
);

/**
 * Moves a field one place up or down. Fields saved before any reorder have no
 * rank key yet, so the first move ranks the whole list in its new order.
 */
export const moveField = bsb.action(
  {
    input: v.object({
      entity: FieldEntitySchema,
      id: Id,
      direction: v.picklist(["up", "down"]),
    }),
    requireTenant: true,
    permission: "custom_fields.manage",
  },
  async ({ entity, id, direction }, { db, auth }) => {
    const { customFields } = db;
    const listed = await customFields.listDefinitions(entity);

    if (!listed.ok) {
      return listed;
    }

    const order = [...listed.data];
    const from = order.findIndex((definition) => definition.id === id);
    const to = direction === "up" ? from - 1 : from + 1;
    const moving = order[from];
    const other = order[to];

    if (moving === undefined || other === undefined) {
      return err(dbError("raised", "The field can't move further.", {}));
    }

    order[to] = moving;
    order[from] = other;

    if (order.every((definition) => definition.rank !== undefined)) {
      const moved = await customFields.reorderDefinition({
        id,
        neighbors: {
          previous: order[to - 1]?.rank ?? null,
          next: order[to + 1]?.rank ?? null,
        },
      });

      if (!moved.ok) {
        return moved;
      }
    } else {
      let previous: string | null = null;

      for (const definition of order) {
        const ranked = await customFields.reorderDefinition({
          id: definition.id,
          neighbors: { previous, next: null },
        });

        if (!ranked.ok) {
          return ranked;
        }

        previous = ranked.data;
      }
    }

    await refreshCaller(auth);

    return ok(true);
  },
);

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function retryCustomFields() {
  refresh();
}
