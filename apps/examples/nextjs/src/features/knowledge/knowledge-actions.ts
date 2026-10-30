"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import { after } from "next/server";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

import { knowledge } from "./knowledge-server";

/**
 * Stores pasted text as one of the caller's documents and embeds it after the
 * response; a queue (`knowledge.embedJob()`) does the same in an app. With a
 * `folderId` the document belongs to that drive folder, and only members who
 * can read the folder find it.
 */
export const addDocument = bsb.action(
  {
    input: v.object({
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      text: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(100_000)),
      folderId: v.optional(v.pipe(v.string(), v.uuid())),
    }),
    requireTenant: true,
    permission: "ai.create",
  },
  async ({ title, text, folderId }, { tenant, supabase }) => {
    const base = knowledge(supabase);

    const document = { title, text, source: "pasted" };

    const created = await (folderId
      ? base.ingest.text(tenant, {
          ...document,
          scope: "subject",
          subject: { type: "drive_node", id: folderId },
        })
      : base.ingest.text(tenant, document));

    if (!created.ok) {
      return created;
    }

    after(() => base.process(created.data.id));
    refresh();

    return ok(created.data.id);
  },
);

export const removeDocument = bsb.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "ai.create",
  },
  async ({ id }, { supabase }) => {
    const removed = await knowledge(supabase).documents.remove(id);

    if (!removed.ok) {
      return removed;
    }

    refresh();

    return ok(removed.data);
  },
);

export interface SearchHit {
  readonly id: string;
  readonly title: string;
  readonly content: string;
  readonly score: number;
}

/** Hybrid search over the documents the caller can read. */
export const searchKnowledge = bsb.action(
  {
    input: v.object({
      query: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(500)),
    }),
    requireTenant: true,
    permission: "ai.create",
  },
  ({ query }, { tenant, supabase }) =>
    knowledge(supabase)
      .search(tenant, query, { k: 5 })
      .map((hits): readonly SearchHit[] =>
        hits.map((hit) => ({
          id: `${hit.documentId}#${String(hit.index)}`,
          title: hit.title,
          content: hit.content,
          score: hit.score,
        })),
      ),
);
