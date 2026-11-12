"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { CONTENT_TAG } from "./content-cache";

const Id = v.pipe(v.string(), v.uuid());

/** Writes a draft page or post. */
export const createEntry = bsb.action(
  {
    input: v.object({
      type: v.picklist(["page", "post"]),
      slug: v.pipe(
        v.string(),
        v.trim(),
        v.regex(/^[a-z0-9]+(?:-[a-z0-9]+)*(?:\/[a-z0-9]+(?:-[a-z0-9]+)*)*$/),
        v.maxLength(120),
      ),
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      summary: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(500))),
    }),
    requireTenant: true,
    permission: "content.write",
  },
  async ({ type, slug, title, summary }, { db, auth }) => {
    const created = summary
      ? await db.content.create({ type, slug, title, summary })
      : await db.content.create({ type, slug, title });

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth, [CONTENT_TAG]);

    return ok(created.data.id);
  },
);

/** Publishes an entry now. */
export const publishEntry = bsb.action(
  {
    input: v.object({ entryId: Id }),
    requireTenant: true,
    permission: "content.publish",
  },
  async ({ entryId }, { db, auth }) => {
    const published = await db.content.publish(entryId);

    if (!published.ok) {
      return published;
    }

    await refreshCaller(auth, [CONTENT_TAG]);

    return ok(published.data.id);
  },
);

/** Takes an entry down. */
export const archiveEntry = bsb.action(
  {
    input: v.object({ entryId: Id }),
    requireTenant: true,
    permission: "content.publish",
  },
  async ({ entryId }, { db, auth }) => {
    const archived = await db.content.archive(entryId);

    if (!archived.ok) {
      return archived;
    }

    await refreshCaller(auth, [CONTENT_TAG]);

    return ok(archived.data.id);
  },
);
