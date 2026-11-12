import "server-only";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { readMemberNames } from "@/features/people/member-names";
import { bsb } from "@/lib/supabase/server";

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/**
 * A failed read becomes `{ kind: "error" }` and is never cached, so Retry reads
 * again.
 */
async function settle<T>(load: () => Promise<T | null>): Promise<Loaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

/** An appraisal as the list shows it, serializable. */
export interface AppraisalRow {
  readonly id: string;
  readonly subjectUserId: string;
  readonly subjectName: string;
  readonly status:
    | "pending"
    | "reviewed"
    | "calibrated"
    | "awaiting_signoff"
    | "signed_off";
  /** The calibrated rating when there is one, else the review average. */
  readonly rating: string | null;
}

async function loadAppraisals(): Promise<readonly AppraisalRow[] | null> {
  "use cache: private";
  const scope = await bsb.cached();
  const { session, db } = scope;
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const [rows, names] = await Promise.all([
    db.appraisals.listAppraisals({ limit: 200 }).orThrow(),
    readMemberNames(scope, tenant),
  ]);

  return rows.map((row) => ({
    id: row.id,
    subjectUserId: row.subjectUserId,
    subjectName: names.get(row.subjectUserId) ?? row.subjectUserId.slice(0, 8),
    status: row.status,
    rating: row.calibratedRating?.toString() ?? row.rating ?? null,
  }));
}

/** The appraisals the caller reads, newest first. */
export function getAppraisals(): Promise<Loaded<readonly AppraisalRow[]>> {
  return settle(loadAppraisals);
}

export interface AppraisalDetailData {
  readonly id: string;
  readonly subjectName: string;
  readonly managerName: string | null;
  readonly cycleName: string | null;
  readonly status: AppraisalRow["status"];
  readonly rating: string | null;
  readonly calibratedRating: number | null;
  readonly signedOffAt: string | null;
  readonly competencies: readonly {
    readonly key: string;
    readonly name: string;
    readonly weight: number;
    readonly average: string | null;
    readonly calibrated: number | null;
  }[];
  readonly reviews: readonly {
    readonly id: string;
    readonly kind: string;
    readonly reviewerName: string | null;
    readonly rating: number | null;
    readonly comments: string | null;
    readonly submittedAt: string | null;
  }[];
  readonly calibrations: readonly {
    readonly id: string;
    readonly toRating: number;
    readonly reason: string;
    readonly calibratedAt: string;
  }[];
}

async function loadAppraisal(
  id: string,
): Promise<AppraisalDetailData | "not-found" | null> {
  "use cache: private";
  const scope = await bsb.cached();
  const { session, db } = scope;
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const found = await db.appraisals.getAppraisal(id);

  if (!found.ok) {
    if (found.error.hint === "APPRAISALS_NOT_FOUND") {
      return "not-found";
    }

    throw new Error(found.error.message);
  }

  const appraisal = found.data;

  const [cycles, names] = await Promise.all([
    db.appraisals.listCycles().orThrow(),
    readMemberNames(scope, tenant),
  ]);

  const name = (userId: string | undefined): string | null =>
    userId === undefined ? null : (names.get(userId) ?? userId.slice(0, 8));

  return {
    id: appraisal.id,
    subjectName: name(appraisal.subjectUserId) ?? appraisal.subjectUserId,
    managerName: name(appraisal.managerId),
    cycleName:
      cycles.find((cycle) => cycle.id === appraisal.cycleId)?.name ?? null,
    status: appraisal.status,
    rating: appraisal.rating ?? null,
    calibratedRating: appraisal.calibratedRating ?? null,
    signedOffAt: appraisal.signedOffAt?.toString() ?? null,
    competencies: appraisal.competencies.map((competency) => ({
      key: competency.key,
      name: competency.name,
      weight: competency.weight,
      average: competency.average ?? null,
      calibrated: competency.calibrated ?? null,
    })),
    reviews: appraisal.reviews.map((review) => ({
      id: review.id,
      kind: review.kind,
      reviewerName: name(review.reviewerId),
      rating: review.rating ?? null,
      comments: review.comments ?? null,
      submittedAt: review.submittedAt?.toString() ?? null,
    })),
    calibrations: appraisal.calibrations.map((calibration) => ({
      id: calibration.id,
      toRating: calibration.toRating,
      reason: calibration.reason,
      calibratedAt: calibration.calibratedAt.toString(),
    })),
  };
}

/** One appraisal with its competencies, reviews and calibrations. */
export function getAppraisal(
  id: string,
): Promise<Loaded<AppraisalDetailData | "not-found">> {
  return settle(() => loadAppraisal(id));
}
