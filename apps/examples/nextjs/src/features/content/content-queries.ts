import "server-only";
import type { ContentStatus } from "better-supabase/blocks/content";

import { cacheTag } from "next/cache";

import { bsb } from "@/lib/supabase/server";

import { CONTENT_TAG } from "./content-cache";

export interface ContentRow {
  readonly id: string;
  readonly type: string;
  readonly locale: string;
  readonly slug: string;
  readonly title: string;
  readonly summary: string | null;
  readonly status: ContentStatus;
  readonly updatedAt: string;
  readonly publishedAt: string | null;
}

/** The newest pages and posts of the organization, drafts included. */
export async function getContentEntries(): Promise<readonly ContentRow[]> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(CONTENT_TAG);

  const entries = await db.content.list({ limit: 100 }).orThrow();

  return entries.map((entry) => ({
    id: entry.id,
    type: entry.type,
    locale: entry.locale,
    slug: entry.slug,
    title: entry.title,
    summary: entry.summary ?? null,
    status: entry.status,
    updatedAt: entry.updatedAt.toString(),
    publishedAt: entry.publishedAt?.toString() ?? null,
  }));
}
