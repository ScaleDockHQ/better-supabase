"use server";

import type { CreateCollectionInput } from "better-supabase/blocks/collections";

import { ok } from "better-supabase";
import * as v from "valibot";

import type { Mutable } from "@/lib/block-status-list";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { COLLECTIONS_TAG } from "./collections-cache";

const Id = v.pipe(v.string(), v.uuid());

/** Creates a collection of customers, personal or shared with the organization. */
export const createCollection = bsb.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(120)),
      scope: v.picklist(["user", "tenant"]),
      description: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(500))),
    }),
    requireTenant: true,
    permission: "collections.write",
  },
  async (
    { name, scope, description },
    { tenant: organizationId, db, auth },
  ) => {
    const input: Mutable<CreateCollectionInput> = {
      name,
      scope,
      subjectType: "customer",
    };

    if (description) {
      input.description = description;
    }

    const created = await db.collections.create({ organizationId, input });

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth, [COLLECTIONS_TAG]);

    return ok(created.data.id);
  },
);

/** Archives a collection, or brings an archived one back. */
export const archiveCollection = bsb.action(
  {
    input: v.object({ collectionId: Id, archived: v.boolean() }),
    requireTenant: true,
    permission: "collections.write",
  },
  async ({ collectionId, archived }, { db, auth }) => {
    const done = await db.collections.archive({ id: collectionId, archived });

    if (!done.ok) {
      return done;
    }

    await refreshCaller(auth, [COLLECTIONS_TAG]);

    return ok(done.data);
  },
);

/** Adds a customer to a collection. */
export const addToCollection = bsb.action(
  {
    input: v.object({ collectionId: Id, subjectId: Id }),
    requireTenant: true,
    permission: "collections.write",
  },
  async ({ collectionId, subjectId }, { db, auth }) => {
    const done = await db.collections.add({
      id: collectionId,
      subjectIds: [subjectId],
    });

    if (!done.ok) {
      return done;
    }

    await refreshCaller(auth, [COLLECTIONS_TAG]);

    return ok(done.data.added.length);
  },
);

/** Takes a customer out of a collection. */
export const removeFromCollection = bsb.action(
  {
    input: v.object({ collectionId: Id, subjectId: Id }),
    requireTenant: true,
    permission: "collections.write",
  },
  async ({ collectionId, subjectId }, { db, auth }) => {
    const done = await db.collections.remove({
      id: collectionId,
      subjectIds: [subjectId],
    });

    if (!done.ok) {
      return done;
    }

    await refreshCaller(auth, [COLLECTIONS_TAG]);

    return ok(done.data);
  },
);
