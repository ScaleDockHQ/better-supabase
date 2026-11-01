import { describe, expect, it } from "vitest";

import { createReviews } from "../../../src/blocks/reviews/index.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, unknown][] = [];

  return {
    calls,
    call(schema: string, fn: string, args: unknown) {
      expect(schema).toBe("better_supabase");
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const AT = "2026-10-06T09:00:00Z";

const REVIEW = {
  id: "r1",
  organizationId: "o",
  subjectType: "product",
  subjectId: "p1",
  authorId: "u1",
  authorName: "Ada",
  mine: true,
  rating: 4,
  title: "Solid",
  body: "Does the job",
  status: "pending",
  verified: true,
  rejectionReason: null,
  reply: null,
  repliedAt: null,
  publishedAt: null,
  createdAt: AT,
  updatedAt: AT,
  fields: {},
};

const PUBLISHED = {
  ...REVIEW,
  authorId: null,
  mine: false,
  status: "published",
  reply: "Thanks",
  repliedAt: AT,
  publishedAt: AT,
};

describe("reviews client", () => {
  it("submits a review and reads the caller's own", async () => {
    const fake = transport({
      submit_review: () => REVIEW,
      my_review: () => null,
    });

    const reviews = createReviews({ transport: fake });

    const review = await reviews
      .submit({
        organizationId: "o",
        subjectType: "product",
        subjectId: "p1",
        input: { rating: 4, body: "Does the job" },
      })
      .orThrow();

    expect(review).toMatchObject({
      id: "r1",
      rating: 4,
      status: "pending",
      verified: true,
      mine: true,
      authorId: "u1",
    });
    expect(review.publishedAt).toBeUndefined();
    expect(review.reply).toBeUndefined();
    expect(review.createdAt.toString()).toBe(AT);
    expect(
      await reviews
        .mine({ organizationId: "o", subjectType: "product", subjectId: "p1" })
        .orThrow(),
    ).toBeUndefined();
    expect(fake.calls).toEqual([
      [
        "submit_review",
        {
          tenant: "o",
          subject_type: "product",
          subject_id: "p1",
          rating: 4,
          body: "Does the job",
          title: null,
          author_name: null,
        },
      ],
      ["my_review", { tenant: "o", subject_type: "product", subject_id: "p1" }],
    ]);
  });

  it("lists published reviews without author ids", async () => {
    const fake = transport({ list_reviews: () => [PUBLISHED] });
    const reviews = createReviews({ transport: fake });

    const [first] = await reviews
      .list({
        organizationId: "o",
        subjectType: "product",
        subjectId: "p1",
        pageSize: 10,
        before: Temporal.Instant.from(AT),
        verified: true,
      })
      .orThrow();

    expect(first?.authorId).toBeUndefined();
    expect(first?.reply).toBe("Thanks");
    expect(first?.publishedAt?.toString()).toBe(AT);
    expect(fake.calls[0]).toEqual([
      "list_reviews",
      {
        tenant: "o",
        subject_type: "product",
        subject_id: "p1",
        page_size: 10,
        before: AT,
        rating: null,
        verified: true,
      },
    ]);
  });

  it("reads the aggregate with a numeric histogram", async () => {
    const fake = transport({
      review_summary: () => ({
        p1: { count: 3, average: "4.33", histogram: { "4": 2, "5": 1 } },
      }),
    });

    const reviews = createReviews({ transport: fake });

    expect(
      await reviews
        .summary({
          organizationId: "o",
          subjectType: "product",
          subjectIds: ["p1", "p2"],
        })
        .orThrow(),
    ).toEqual({ p1: { count: 3, average: 4.33, histogram: { 4: 2, 5: 1 } } });
  });

  it("moderates through the queue", async () => {
    const fake = transport({
      review_queue: () => [REVIEW],
      publish_review: () => PUBLISHED,
      reject_review: () => ({
        ...REVIEW,
        status: "rejected",
        rejectionReason: "Off topic",
      }),
      reply_to_review: () => PUBLISHED,
      delete_review: () => false,
    });

    const reviews = createReviews({ transport: fake });

    expect(await reviews.queue({ organizationId: "o" }).orThrow()).toHaveLength(
      1,
    );
    await reviews
      .queue({ organizationId: "o", status: null, subjectId: "p1" })
      .orThrow();
    expect((await reviews.publish("r1").orThrow()).status).toBe("published");
    expect(
      (await reviews.reject({ reviewId: "r1", reason: "Off topic" }).orThrow())
        .rejectionReason,
    ).toBe("Off topic");
    await reviews.reply({ reviewId: "r1", reply: null }).orThrow();
    expect(await reviews.remove("r1").orThrow()).toBe(false);
    expect(fake.calls).toEqual([
      [
        "review_queue",
        {
          tenant: "o",
          status: "pending",
          page_size: null,
          before: null,
          subject_type: null,
          subject_id: null,
        },
      ],
      [
        "review_queue",
        {
          tenant: "o",
          status: null,
          page_size: null,
          before: null,
          subject_type: null,
          subject_id: "p1",
        },
      ],
      ["publish_review", { review_id: "r1" }],
      ["reject_review", { review_id: "r1", reason: "Off topic" }],
      ["reply_to_review", { review_id: "r1", reply: null }],
      ["delete_review", { review_id: "r1" }],
    ]);
  });

  it("rejects an unknown status", async () => {
    const fake = transport({
      publish_review: () => ({ ...REVIEW, status: "hidden" }),
    });

    const result = await createReviews({ transport: fake }).publish("r1");
    expect(result.ok).toBe(false);
  });
});
