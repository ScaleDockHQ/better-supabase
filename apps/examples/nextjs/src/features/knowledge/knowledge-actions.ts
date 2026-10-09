"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import { after } from "next/server";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { bs } from "@/lib/supabase/server";

import { knowledge } from "./knowledge-server";

/**
 * Stores pasted text as one of the caller's documents and embeds it after
 * the response; a queue (`knowledge.embedJob()`) does the same in an app.
 */
export const addDocument = bs.action(
  {
    input: v.object({
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      text: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(100_000)),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "ai.create"),
  },
  async ({ title, text }, { tenant, supabase }) => {
    const base = knowledge(supabase);
    const created = await base.ingest.text(tenant, {
      title,
      text,
      source: "pasted",
    });
    if (!created.ok) return created;
    after(() => base.process(created.data.id));
    refresh();
    return ok(created.data.id);
  },
);

export const removeDocument = bs.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    authorize: (session) => can(session, "ai.create"),
  },
  async ({ id }, { supabase }) => {
    const removed = await knowledge(supabase).documents.remove(id);
    if (!removed.ok) return removed;
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
export const searchKnowledge = bs.action(
  {
    input: v.object({
      query: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(500)),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "ai.create"),
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
