"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import { after } from "next/server";
import * as v from "valibot";

import { bsbCore } from "@/lib/supabase/server-core";

import { knowledge } from "./knowledge-server";

/**
 * Stores pasted text as one of the caller's documents and embeds it after the
 * response; a queue (`knowledge.embedJob()`) does the same in an app. With a
 * `folderId` the document belongs to that drive folder, and only members who
 * can read the folder find it.
 */
export const addDocument = bsbCore.action(
  {
    input: v.object({
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      text: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(100_000)),
      folderId: v.optional(v.pipe(v.string(), v.uuid())),
    }),
    requireTenant: true,
    permission: "knowledge.write",
  },
  async ({ title, text, folderId }, { tenant, supabase }) => {
    const base = knowledge(supabase);

    const document = { title, text, source: "pasted" };

    const created = await (folderId
      ? base.ingest.text({
          organizationId: tenant,
          document: {
            ...document,
            scope: "subject",
            subject: { type: "drive_node", id: folderId },
          },
        })
      : base.ingest.text({ organizationId: tenant, document }));

    if (!created.ok) {
      return created;
    }

    after(() => base.process({ documentId: created.data.id }));
    refresh();

    return ok(created.data.id);
  },
);

export const removeDocument = bsbCore.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "knowledge.write",
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
  /** The best score of the search, so the playground can draw a relative bar. */
  readonly best: number;
}

/** Hybrid search over the documents the caller can read. */
export const searchKnowledge = bsbCore.action(
  {
    input: v.object({
      query: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(500)),
      k: v.optional(
        v.pipe(
          v.string(),
          v.transform(Number),
          v.integer(),
          v.minValue(1),
          v.maxValue(20),
        ),
      ),
      // An empty select posts "": every scope.
      scope: v.optional(
        v.picklist(["", "organization", "agent", "project", "chat", "user"]),
      ),
      // A checkbox posts nothing when it is off.
      byScoreOnly: v.optional(v.string()),
    }),
    requireTenant: true,
    permission: "knowledge.write",
  },
  ({ query, k, scope, byScoreOnly }, { tenant, supabase }) =>
    knowledge(supabase)
      .search({
        organizationId: tenant,
        query,
        k: k ?? 5,
        ...(scope === undefined || scope === "" ? {} : { scopes: [{ scope }] }),
        ...(byScoreOnly === undefined ? {} : { priorityOrder: false }),
      })
      .map((hits): readonly SearchHit[] => {
        const best = hits.reduce((max, hit) => Math.max(max, hit.score), 0);

        return hits.map((hit) => ({
          id: `${hit.documentId}#${String(hit.index)}`,
          title: hit.title,
          content: hit.content,
          score: hit.score,
          best,
        }));
      }),
);
