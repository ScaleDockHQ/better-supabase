import "server-only";
import type { MyWorkKind } from "better-supabase/blocks/subjects";

import { tenantOf } from "better-supabase/next";
import { loadMyWork } from "better-supabase/records";
import { cacheTag } from "next/cache";
import { unstable_rethrow } from "next/navigation";

import { APPROVALS_TAG } from "@/features/approvals/approvals-cache";
import { CALENDAR_TAG } from "@/features/calendar/calendar-cache";
import { CRM_TAG } from "@/features/crm/crm-cache";
import { CUSTOMERS_TAG } from "@/features/customers/customers-cache";
import { PROJECTS_TAG } from "@/features/projects/projects-cache";
import { WORK_TAG } from "@/features/work/work-cache";
import { bsb } from "@/lib/supabase/server";

export interface MyWorkRow {
  readonly key: string;
  readonly kind: MyWorkKind;
  readonly title: string;
  readonly url: string | null;
  /** Epoch milliseconds: the due date, or when it arrived. */
  readonly at: number | null;
}

export interface MyWorkView {
  readonly rows: readonly MyWorkRow[];
  readonly counts: Readonly<Record<MyWorkKind, number>>;
}

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "no-organization" }
  | { readonly kind: "error" };

/**
 * What waits on the caller in the organization: assigned work, approvals, due
 * reminders, mentions and SLA warnings. Throws on a failed read, so the private
 * cache never keeps an error.
 */
async function loadView(): Promise<MyWorkView | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(
    WORK_TAG,
    PROJECTS_TAG,
    APPROVALS_TAG,
    CALENDAR_TAG,
    CUSTOMERS_TAG,
    CRM_TAG,
  );
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const work = await loadMyWork(db.subjects, { tenant }).orThrow();

  return {
    rows: work.items.map((item) => ({
      key: `${item.kind}:${item.ref}`,
      kind: item.kind,
      title: item.title ?? item.subject.id,
      url: item.url ?? null,
      at: item.at?.epochMilliseconds ?? null,
    })),
    counts: work.counts,
  };
}

export async function getMyWork(): Promise<Loaded<MyWorkView>> {
  try {
    const data = await loadView();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

export interface MyReminder {
  readonly id: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly offsetMinutes: number;
  /** Epoch milliseconds of a one-time reminder. */
  readonly remindAt: number | null;
}

/**
 * Every reminder the caller set, on any subject. Throws on a failed read, so
 * the private cache never keeps an error.
 */
async function loadReminders(): Promise<readonly MyReminder[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(CALENDAR_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const reminders = await db.reminders.listForCaller({ limit: 100 }).orThrow();

  return reminders.map((reminder) => ({
    id: reminder.id,
    subjectType: reminder.subject.type,
    subjectId: reminder.subject.id,
    offsetMinutes: reminder.offsetMinutes,
    remindAt: reminder.remindAt?.epochMilliseconds ?? null,
  }));
}

export async function getMyReminders(): Promise<Loaded<readonly MyReminder[]>> {
  try {
    const data = await loadReminders();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
