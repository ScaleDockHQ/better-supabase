import "server-only";
import type { ContentStatus } from "better-supabase/blocks/content";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { orMissing } from "@/lib/or-missing";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

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

/** One entry for its page, with the dates as ISO text. */
export interface ContentDetailRow extends ContentRow {
  readonly publishAt: string | null;
  readonly approvalStatus: string | null;
  readonly translations: number;
}

/**
 * The entry; `undefined` when it does not exist, `null` without an
 * organization.
 */
export async function getContentEntry(
  id: string,
): Promise<ContentDetailRow | undefined | null> {
  "use cache: private";
  const { db, session } = await bsb.cached();
  cacheTag(tags.contentEntries());

  if (!tenantOf(session)) {
    return null;
  }

  const entry = orMissing(await db.content.get(id));

  if (entry === undefined || entry === null) {
    return undefined;
  }

  return {
    id: entry.id,
    type: entry.type,
    locale: entry.locale,
    slug: entry.slug,
    title: entry.title,
    summary: entry.summary ?? null,
    status: entry.status,
    updatedAt: entry.updatedAt.toString(),
    publishedAt: entry.publishedAt?.toString() ?? null,
    publishAt: entry.publishAt?.toString() ?? null,
    approvalStatus: entry.approvalStatus ?? null,
    translations: entry.translations?.length ?? 0,
  };
}
