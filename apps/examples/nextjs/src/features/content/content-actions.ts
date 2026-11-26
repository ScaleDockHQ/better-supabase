"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

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
    tags: () => [tags.contentEntries()],
    refresh: true,
  },
  async ({ type, slug, title, summary }, { db }) => {
    const created = summary
      ? await db.content.create({ type, slug, title, summary })
      : await db.content.create({ type, slug, title });

    if (!created.ok) {
      return created;
    }

    return ok(created.data.id);
  },
);

/** Publishes an entry now. */
export const publishEntry = bsb.blockAction(
  ({ db }) => db.content,
  "publish",
  {
    input: v.object({ entryId: Id }),
    requireTenant: true,
    permission: "content.publish",
    tags: () => [tags.contentEntries()],
    refresh: true,
    args: ({ entryId }) => [entryId],
  },
  (published) => published.id,
);

/** Takes an entry down. */
export const archiveEntry = bsb.blockAction(
  ({ db }) => db.content,
  "archive",
  {
    input: v.object({ entryId: Id }),
    requireTenant: true,
    permission: "content.publish",
    tags: () => [tags.contentEntries()],
    refresh: true,
    args: ({ entryId }) => [entryId],
  },
  (archived) => archived.id,
);
