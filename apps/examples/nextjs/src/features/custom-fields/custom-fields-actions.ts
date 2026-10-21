"use server";

import { dbError, err, ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

import { FieldEntitySchema, FieldTypeSchema } from "./custom-fields-types";

const Id = v.pipe(v.string(), v.uuid());

/**
 * Adds a field, or relabels the entity's field with the same key. Keys are
 * lower snake case, since they name the value in the API.
 */
export const saveField = bs.action(
  {
    input: v.object({
      entity: FieldEntitySchema,
      key: v.pipe(v.string(), v.trim(), v.regex(/^[a-z][a-z0-9_]{0,62}$/u)),
      label: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(80)),
      type: FieldTypeSchema,
      sensitive: v.optional(v.boolean(), false),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "custom_fields.manage"),
  },
  async (
    { entity, key, label, type, sensitive },
    { tenant, supabase, auth },
  ) => {
    const saved = await blocks(supabase, tenant).customFields.saveDefinition(
      entity,
      key,
      label,
      type,
      sensitive,
    );

    if (!saved.ok) {
      return saved;
    }

    refreshCaller(auth);

    return ok(saved.data.id);
  },
);

export const deleteField = bs.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "custom_fields.manage"),
  },
  async ({ id }, { supabase, auth }) => {
    const deleted = await blocks(supabase).customFields.deleteDefinition(id);

    if (!deleted.ok) {
      return deleted;
    }

    refreshCaller(auth);

    return ok(deleted.data);
  },
);

/**
 * Moves a field one place up or down. Fields saved before any reorder have no
 * rank key yet, so the first move ranks the whole list in its new order.
 */
export const moveField = bs.action(
  {
    input: v.object({
      entity: FieldEntitySchema,
      id: Id,
      direction: v.picklist(["up", "down"]),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "custom_fields.manage"),
  },
  async ({ entity, id, direction }, { tenant, supabase, auth }) => {
    const { customFields } = blocks(supabase, tenant);
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
      const moved = await customFields.reorderDefinition(id, {
        previous: order[to - 1]?.rank ?? null,
        next: order[to + 1]?.rank ?? null,
      });

      if (!moved.ok) {
        return moved;
      }
    } else {
      let previous: string | null = null;

      for (const definition of order) {
        const ranked = await customFields.reorderDefinition(definition.id, {
          previous,
          next: null,
        });

        if (!ranked.ok) {
          return ranked;
        }

        previous = ranked.data;
      }
    }

    refreshCaller(auth);

    return ok(true);
  },
);

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function retryCustomFields() {
  refresh();
}
