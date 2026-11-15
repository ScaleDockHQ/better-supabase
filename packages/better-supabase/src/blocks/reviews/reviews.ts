import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type {
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { CountOptions, FacetOptions } from "../../core/entity-list.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { entityList } from "../../core/entity-list.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { reviewListSurface } from "./lists.ts";

export interface ReviewsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the review's extra columns (columns the app's schema
   * files add to the table), keyed by database name. It types and parses them
   * on reads, and validates them on `submit`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Reviews<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

export type ReviewStatus = "pending" | "published" | "rejected";

/** A review. `F` types the extra columns the `fields` schema describes. */
export interface Review<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /**
   * Missing on `list`, which hides who wrote each review; `mine` marks the
   * caller's.
   */
  readonly authorId?: string;
  readonly authorName?: string;
  /** Whether the caller wrote it. */
  readonly mine: boolean;
  /** From 1 to `blocks.reviews.options.scale` (default 5). */
  readonly rating: number;
  readonly title?: string;
  readonly body?: string;
  readonly status: ReviewStatus;
  /** Whether the orders module shows a paid order for the product. */
  readonly verified: boolean;
  /** Why a moderator rejected it; the author sees it. */
  readonly rejectionReason?: string;
  /** The organization's public reply. */
  readonly reply?: string;
  readonly repliedAt?: Temporal.Instant;
  readonly publishedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface ReviewInput<F extends object = Record<never, never>> {
  readonly rating: number;
  readonly body?: string;
  readonly title?: string;
  /** The name shown with the review. */
  readonly authorName?: string;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

/** The subject whose reviews a page reads. */
export interface ReviewSubject {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
}

export interface ReviewListOptions {
  readonly pageSize?: number;
  /** Reviews published before this instant, for the next page. */
  readonly before?: Temporal.Instant;
  /** Only this rating. */
  readonly rating?: number;
  /** Only verified (`true`) or unverified (`false`) reviews. */
  readonly verified?: boolean;
}

export interface ReviewQueueOptions {
  /** Default `pending`; `null` lists every status. */
  readonly status?: ReviewStatus | null;
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly pageSize?: number;
  /** Reviews written before this instant, for the next page. */
  readonly before?: Temporal.Instant;
}

/** One subject's published reviews, counted. */
export interface ReviewSummary {
  readonly count: number;
  /** The mean rating, rounded to two decimals. */
  readonly average: number;
  /** How many reviews gave each rating, keyed by rating. */
  readonly histogram: Readonly<Record<number, number>>;
}

export interface Reviews<F extends object = Record<never, never>> {
  /**
   * Writes the caller's review of a subject, or replaces it (one per user and
   * subject). It waits for `publish` under pre-moderation.
   */
  submit(input: {
    organizationId: string;
    subjectType: string;
    subjectId: string;
    input: ReviewInput<F>;
  }): AsyncResult<Review<F>>;
  /** The caller's review of the subject in any status. */
  mine(input: {
    organizationId: string;
    subjectType: string;
    subjectId: string;
  }): AsyncResult<Review<F> | undefined>;
  /**
   * The subject's published reviews, newest first. Anonymous visitors can call
   * it for a public storefront's products.
   *
   * @deprecated Use `reviewPage`, which pages by keyset and takes `q`, sorts,
   * array filters and a count (ADR 1077).
   */
  list(
    input: {
      organizationId: string;
      subjectType: string;
      subjectId: string;
    } & ReviewListOptions,
  ): AsyncResult<readonly Review<F>[]>;
  /**
   * One keyset page of a subject's published reviews, newest first. `filters`
   * takes `rating` and `verified` (lists); `q` searches the title and the body.
   * Anonymous visitors can call it for a public storefront's products.
   */
  reviewPage(
    input: ReviewSubject & PageOptions,
  ): AsyncResult<ListPage<Review<F>>>;
  /** The values of each facet (`rating`, `verified`) under the page's filters. */
  reviewFacets(
    input: ReviewSubject & FacetOptions,
  ): AsyncResult<readonly FacetResult[]>;
  /** How many published reviews of the subject match the page's filters. */
  reviewCount(input: ReviewSubject & CountOptions): AsyncResult<Count>;
  /** One review by id, or a `not_found` error. */
  get(reviewId: string): AsyncResult<Review<F>>;
  /**
   * The rating aggregate of up to 200 subjects of one type, by subject id.
   * Subjects without published reviews are left out.
   */
  summary(input: {
    organizationId: string;
    subjectType: string;
    subjectIds: readonly string[];
  }): AsyncResult<Readonly<Record<string, ReviewSummary>>>;
  /** Reviews for moderators, newest first; needs `reviews.manage`. */
  queue(
    input: { organizationId: string } & ReviewQueueOptions,
  ): AsyncResult<readonly Review<F>[]>;
  /** Needs `reviews.manage`. */
  publish(reviewId: string): AsyncResult<Review<F>>;
  /** Needs `reviews.manage`. */
  reject(input: {
    reviewId: string;
    reason?: string | undefined;
  }): AsyncResult<Review<F>>;
  /**
   * Sets the organization's public reply; `null` removes it. Needs
   * `reviews.manage`.
   */
  reply(input: {
    reviewId: string;
    reply: string | null;
  }): AsyncResult<Review<F>>;
  /** The author or a moderator; `false` when the review is gone. */
  remove(reviewId: string): AsyncResult<boolean>;
}

const STATUSES: readonly ReviewStatus[] = ["pending", "published", "rejected"];

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

function reviewOf(value: unknown, fn: string): Review {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    mine: row["mine"] === true,
    rating: typeof row["rating"] === "number" ? row["rating"] : 0,
    status: enumOrThrow(row["status"], STATUSES, "review status"),
    verified: row["verified"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("authorId", optionalText(row["authorId"])),
    ...optional("authorName", optionalText(row["authorName"])),
    ...optional("title", optionalText(row["title"])),
    ...optional("body", optionalText(row["body"])),
    ...optional("rejectionReason", optionalText(row["rejectionReason"])),
    ...optional("reply", optionalText(row["reply"])),
    ...optional("repliedAt", optionalInstant(row["repliedAt"])),
    ...optional("publishedAt", optionalInstant(row["publishedAt"])),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function summaryOf(value: unknown): Readonly<Record<string, ReviewSummary>> {
  const out: Record<string, ReviewSummary> = {};

  for (const [id, entry] of Object.entries(recordOf(value, "review_summary"))) {
    const row = isRecord(entry) ? entry : {};
    const histogram: Record<number, number> = {};

    for (const [rating, count] of Object.entries(
      isRecord(row["histogram"]) ? row["histogram"] : {},
    )) {
      if (typeof count === "number") {
        histogram[Number(rating)] = count;
      }
    }

    out[id] = {
      count: typeof row["count"] === "number" ? row["count"] : 0,
      average: Number(row["average"] ?? 0),
      histogram,
    };
  }

  return out;
}

/** The `reviews` SQL module as typed calls. */
export function createReviews<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: ReviewsOptions<S>): Reviews<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "review fields");

  const one =
    (fn: string) =>
    (value: unknown): Review =>
      reviewOf(value, fn);

  const many =
    (fn: string) =>
    (value: unknown): readonly Review[] =>
      recordsOf(value, fn).map((row) => reviewOf(row, fn));

  const reviews = entityList<Review, { readonly organizationId: string }>({
    entity: "review",
    surface: reviewListSurface,
    call,
    tenant: (organizationId) => AsyncResult.ok(organizationId ?? ""),
    fn: "page_reviews",
    rowOf: reviewOf,
  });

  // The page reads one subject, which the SQL function takes as two filters.
  const ofSubject = <T extends { readonly filters?: PageOptions["filters"] }>(
    input: ReviewSubject & T,
  ) => {
    const { subjectType, subjectId, filters, ...rest } = input;

    return {
      ...rest,
      filters: {
        ...filters,
        subjectType: [subjectType],
        subjectId: [subjectId],
      },
    };
  };

  const client: Reviews<F> = {
    submit: ({ organizationId, subjectType, subjectId, input }) =>
      fields
        .args(input.fields)
        .andThen((checked) =>
          call(
            "submit_review",
            {
              tenant: organizationId,
              subject_type: subjectType,
              subject_id: subjectId,
              rating: input.rating,
              body: input.body ?? null,
              title: input.title ?? null,
              author_name: input.authorName ?? null,
              ...(checked === undefined ? {} : { fields: checked }),
            },
            one("submit_review"),
          ).andThen(fields.row),
        ),
    mine: ({ organizationId, subjectType, subjectId }) =>
      call(
        "my_review",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
        },
        (value) =>
          value === null || value === undefined
            ? undefined
            : reviewOf(value, "my_review"),
      ).andThen((review) =>
        review === undefined ? AsyncResult.ok(undefined) : fields.row(review),
      ),
    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated alias is still implemented until 0.70 (ADR 1077)
    list: ({ organizationId, subjectType, subjectId, ...list }) =>
      call(
        "list_reviews",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
          page_size: list.pageSize ?? null,
          before: instantArg(list.before) ?? null,
          rating: list.rating ?? null,
          verified: list.verified ?? null,
        },
        many("list_reviews"),
      ).andThen(fields.rows),
    reviewPage: (input) =>
      reviews
        .page(ofSubject(input))
        .andThen((read) =>
          fields.rows(read.items).map((items) => ({ ...read, items })),
        ),
    reviewFacets: (input) => reviews.facets(ofSubject(input)),
    reviewCount: (input) => reviews.count(ofSubject(input)),
    get: (reviewId) =>
      call("get_review", { review_id: reviewId }, one("get_review")).andThen(
        fields.row,
      ),
    summary: ({ organizationId, subjectType, subjectIds }) =>
      call(
        "review_summary",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_ids: subjectIds,
        },
        summaryOf,
      ),
    queue: ({ organizationId, ...queue }) =>
      call(
        "review_queue",
        {
          tenant: organizationId,
          status: queue.status === undefined ? "pending" : queue.status,
          page_size: queue.pageSize ?? null,
          before: instantArg(queue.before) ?? null,
          subject_type: queue.subjectType ?? null,
          subject_id: queue.subjectId ?? null,
        },
        many("review_queue"),
      ).andThen(fields.rows),
    publish: (reviewId) =>
      call(
        "publish_review",
        { review_id: reviewId },
        one("publish_review"),
      ).andThen(fields.row),
    reject: ({ reviewId, reason }) =>
      call(
        "reject_review",
        { review_id: reviewId, reason: reason ?? null },
        one("reject_review"),
      ).andThen(fields.row),
    reply: ({ reviewId, reply }) =>
      call(
        "reply_to_review",
        { review_id: reviewId, reply },
        one("reply_to_review"),
      ).andThen(fields.row),
    remove: (reviewId) =>
      call("delete_review", { review_id: reviewId }, (value) => value === true),
  };

  return withBlockHooks(client, options.hooks, {
    block: "reviews",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
