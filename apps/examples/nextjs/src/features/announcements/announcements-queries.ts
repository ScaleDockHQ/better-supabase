import "server-only";
import type { AnnouncementSeverity } from "better-supabase/blocks/announcements";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { bsb } from "@/lib/supabase/server";

import { ANNOUNCEMENTS_TAG } from "./announcements-cache";

export interface AnnouncementRow {
  readonly id: string;
  readonly title: string;
  readonly body: string;
  readonly severity: AnnouncementSeverity;
  readonly href: string | null;
  readonly startsAt: string;
  readonly endsAt: string | null;
  readonly dismissible: boolean;
}

/** The live announcements the caller has not dismissed, newest first. */
export async function getAnnouncements(): Promise<readonly AnnouncementRow[]> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(ANNOUNCEMENTS_TAG);

  const active = await db.announcements
    .listActive(tenantOf(session) ?? null)
    .orThrow();

  return active.map((announcement) => ({
    id: announcement.id,
    title: announcement.title,
    body: announcement.body,
    severity: announcement.severity,
    href: announcement.href ?? null,
    startsAt: announcement.startsAt.toString(),
    endsAt: announcement.endsAt?.toString() ?? null,
    dismissible: announcement.dismissible,
  }));
}
