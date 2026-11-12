import "server-only";
import type {
  ModerationActionKind,
  ModerationStatus,
} from "better-supabase/blocks/moderation";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { bsb } from "@/lib/supabase/server";

import { MODERATION_TAG } from "./moderation-cache";

export interface QueueRow {
  readonly id: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly status: ModerationStatus;
  readonly openReports: number;
  readonly reason: string | null;
  readonly updatedAt: string;
}

/** What needs a moderator: pending content and content with open reports. */
export async function getQueue(): Promise<readonly QueueRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(MODERATION_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const items = await db.moderation.queue({ pageSize: 50 }).orThrow();

  return items.map((item) => ({
    id: item.id,
    subjectType: item.subject.type,
    subjectId: item.subject.id,
    status: item.status,
    openReports: item.openReports,
    reason: item.reason ?? null,
    updatedAt: item.updatedAt.toString(),
  }));
}

export interface BanRow {
  readonly id: string;
  readonly userId: string;
  readonly reason: string | null;
  readonly expiresAt: string | null;
  readonly createdAt: string;
}

/** The active bans of the organization, newest first. */
export async function getBans(): Promise<readonly BanRow[]> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(MODERATION_TAG);

  const bans = await db.moderation.bans({ pageSize: 50 }).orThrow();

  return bans.map((ban) => ({
    id: ban.id,
    userId: ban.userId,
    reason: ban.reason ?? null,
    expiresAt: ban.expiresAt?.toString() ?? null,
    createdAt: ban.createdAt.toString(),
  }));
}

export interface ItemDetailData extends QueueRow {
  readonly reports: readonly {
    readonly id: string;
    readonly reason: string;
    readonly note: string | null;
    readonly status: string;
    readonly createdAt: string;
  }[];
  readonly actions: readonly {
    readonly id: string;
    readonly action: ModerationActionKind;
    readonly toStatus: ModerationStatus;
    readonly reason: string | null;
    readonly createdAt: string;
  }[];
}

/** One moderated subject with its reports and log; `null` when untouched. */
export async function getItem(
  type: string,
  id: string,
): Promise<ItemDetailData | null> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(MODERATION_TAG);

  const item = await db.moderation.item({ type, id }).orThrow();

  if (!item) {
    return null;
  }

  return {
    id: item.id,
    subjectType: item.subject.type,
    subjectId: item.subject.id,
    status: item.status,
    openReports: item.openReports,
    reason: item.reason ?? null,
    updatedAt: item.updatedAt.toString(),
    reports: item.reports.map((report) => ({
      id: report.id,
      reason: report.reason,
      note: report.note ?? null,
      status: report.status,
      createdAt: report.createdAt.toString(),
    })),
    actions: item.actions.map((action) => ({
      id: action.id,
      action: action.action,
      toStatus: action.toStatus,
      reason: action.reason ?? null,
      createdAt: action.createdAt.toString(),
    })),
  };
}
