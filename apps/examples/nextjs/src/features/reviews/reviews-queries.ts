import "server-only";
import type { Result } from "better-supabase";
import type {
  Review,
  ReviewQueueOptions,
} from "better-supabase/blocks/reviews";

import { ok } from "better-supabase";
import { subjectKey } from "better-supabase/blocks/subjects";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { Temporal } from "temporal-polyfill";

import type { BlockPage } from "@/lib/block-page";
import type { BlockListQuery, Mutable } from "@/lib/block-status-list";

import { pageOverStatuses } from "@/lib/block-page";
import { bsb } from "@/lib/supabase/server";

import type { ReviewRow } from "./review-row";

import { REVIEWS_TAG } from "./reviews-cache";
import { REVIEW_PAGE_SIZE, REVIEW_STATUSES, reviewList } from "./reviews-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

const isStatus = (value: string): value is ReviewRow["status"] =>
  REVIEW_STATUSES.some((status) => status === value);

const EXCERPT_LENGTH = 120;

function toRow(review: Review): ReviewRow {
  const body = review.body ?? null;

  return {
    id: review.id,
    title: review.title ?? null,
    excerpt:
      body !== null && body.length > EXCERPT_LENGTH
        ? `${body.slice(0, EXCERPT_LENGTH)}…`
        : body,
    author: review.authorName ?? null,
    rating: review.rating,
    status: review.status,
    verified: review.verified,
    subject: review.subjectType,
    subjectType: review.subjectType,
    subjectId: review.subjectId,
    createdAt: review.createdAt.toString(),
  };
}

/** Replaces each row's subject type with the subject's name, in one call. */
async function nameSubjects(
  db: Db,
  rows: readonly ReviewRow[],
): Promise<readonly ReviewRow[]> {
  if (rows.length === 0) {
    return rows;
  }

  const labels = await db.subjects.label(
    rows.map((row) => ({ type: row.subjectType, id: row.subjectId })),
  );

  if (!labels.ok) {
    return rows;
  }

  return rows.map((row) => {
    const named =
      labels.data[subjectKey({ type: row.subjectType, id: row.subjectId })];

    return named?.found === true ? { ...row, subject: named.label } : row;
  });
}

/** One page of the moderation queue, shared by the page and the list route. */
export async function loadReviewPage(
  db: Db,
  organizationId: string,
  query: BlockListQuery<"newest">,
): Promise<Result<BlockPage<ReviewRow>>> {
  const before =
    query.after === undefined ? undefined : Temporal.Instant.from(query.after);

  const page = await pageOverStatuses({
    statuses: query.facets["status"],
    size: REVIEW_PAGE_SIZE,
    fetchPage: (status, take) => {
      const options: Mutable<ReviewQueueOptions> = {
        pageSize: take,
        // The queue lists the pending ones by default; no facet means all.
        status: status !== undefined && isStatus(status) ? status : null,
      };

      if (before !== undefined) {
        options.before = before;
      }

      return db.reviews.queue({ organizationId, ...options });
    },
    map: toRow,
  });

  if (!page.ok) {
    return page;
  }

  return ok({ ...page.data, items: await nameSubjects(db, page.data.items) });
}

/** The first page of reviews, for the instant shell. */
export async function getReviews(): Promise<BlockPage<ReviewRow> | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(REVIEWS_TAG);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const result = await loadReviewPage(db, organizationId, reviewList.defaults);

  if (!result.ok) {
    throw new Error(result.error.message);
  }

  return result.data;
}

export interface ReviewDetailData extends ReviewRow {
  readonly body: string | null;
  readonly reply: string | null;
  readonly rejectionReason: string | null;
}

/** One review; `null` when it is not in the queue. */
export async function getReview(id: string): Promise<ReviewDetailData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(REVIEWS_TAG);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const result = await db.reviews.queue({
    organizationId,
    status: null,
    pageSize: 100,
  });

  if (!result.ok) {
    throw new Error(result.error.message);
  }

  const review = result.data.find((row) => row.id === id);

  if (review === undefined) {
    return null;
  }

  const [named] = await nameSubjects(db, [toRow(review)]);

  return {
    ...(named ?? toRow(review)),
    body: review.body ?? null,
    reply: review.reply ?? null,
    rejectionReason: review.rejectionReason ?? null,
  };
}
