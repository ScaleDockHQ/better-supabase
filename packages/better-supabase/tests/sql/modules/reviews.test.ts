import { describe, expect, it } from "vitest";

import { customContracts, renderModules } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderModules>[1];

const sqlOf = (
  modules: readonly string[],
  layout: Layout = {},
  module = "reviews",
): string =>
  renderModules(modules, layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const COMMERCE = ["catalog", "orders", "reviews"];

const options = (value: Record<string, unknown>): Layout => ({
  modules: { reviews: { options: value } },
});

describe("reviews module", () => {
  it("keeps one review per user and subject, pending until published", () => {
    const sql = sqlOf(COMMERCE);
    expect(sql).toContain(
      `unique ("tenant_id", "subject_type", "subject_id", "author_id")`,
    );
    expect(sql).toContain(
      `check ("status" in ('pending', 'published', 'rejected'))`,
    );
    expect(sql).toContain(`'pending', v_verified, null)`);
  });

  it("publishes at once under post-moderation", () => {
    const sql = sqlOf(COMMERCE, options({ moderation: "post" }));
    expect(sql).toContain(`'published', v_verified, now())`);
    expect(() => sqlOf(COMMERCE, options({ moderation: "never" }))).toThrow(
      /moderation must be "pre" or "post"/,
    );
  });

  it("reads products on a public storefront or with catalog.read", () => {
    const sql = sqlOf(COMMERCE);
    expect(sql).toContain(
      `when 'product' then exists (select 1 from "better_supabase"."products" p`,
    );
    expect(sql).toContain(`'catalog.read'`);
    expect(sql).not.toContain("storefront_products");

    const open = sqlOf(COMMERCE, {
      modules: { catalog: { options: { storefront: "public" } } },
    });

    expect(open).toContain(`"better_supabase"."storefront_products"()`);
    expect(open).toContain(
      `grant execute on function "better_supabase"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) to anon, authenticated, service_role;`,
    );
  });

  it("verifies purchases against paid, uncancelled orders", () => {
    const sql = sqlOf(COMMERCE);
    expect(sql).toContain(`"paid_at" is not null and o."cancelled_at" is null`);
    expect(sql).not.toContain("REVIEW_PURCHASE_REQUIRED");
    expect(sqlOf(["catalog", "reviews"])).toContain("v_verified := false;");
  });

  it("requires a purchase with requirePurchase, which needs orders", () => {
    expect(sqlOf(COMMERCE, options({ requirePurchase: true }))).toContain(
      "REVIEW_PURCHASE_REQUIRED",
    );
    expect(() =>
      sqlOf(["catalog", "reviews"], options({ requirePurchase: true })),
    ).toThrow(/requirePurchase needs the orders block/);
  });

  it("reviews registered subjects for members of their organization", () => {
    const sql = sqlOf(
      ["reviews"],
      options({ subjects: { course: { table: "courses" } } }),
    );

    expect(sql).not.toContain("when 'product'");
    expect(sql).toContain(`"better_supabase"."memberships" m`);
    expect(sql).toContain(`"public"."courses"`);
    expect(sqlOf(["reviews"])).toContain("  return false;");
  });

  it("checks the rating against options.scale", () => {
    expect(sqlOf(COMMERCE)).toContain(`check ("rating" between 1 and 5)`);
    expect(sqlOf(COMMERCE, options({ scale: 10 }))).toContain(
      "rating must be from 1 to 10",
    );

    for (const scale of [1, 11, 2.5]) {
      expect(() => sqlOf(COMMERCE, options({ scale }))).toThrow(/scale/);
    }

    expect(() => sqlOf(COMMERCE, options({ maxBodyLength: 0 }))).toThrow(
      /maxBodyLength/,
    );
  });

  it("gates moderation on reviews.manage and keeps the aggregate in step", () => {
    const sql = sqlOf(COMMERCE);
    expect(sql).toContain(`'reviews.manage'`);
    expect(sql).toContain("not allowed to moderate reviews");
    expect(sql).toContain(
      `after insert or update of "rating", "status" or delete on "better_supabase"."reviews"`,
    );
    expect(sql).toContain(
      `revoke execute on function "better_supabase"."review_stats_refresh"(uuid, text, text) from public, anon, authenticated;`,
    );
  });

  it("notifies the author only with notifications installed", () => {
    expect(sqlOf(COMMERCE)).not.toContain("Your review was published");
    expect(sqlOf([...COMMERCE, "notifications"])).toContain(
      "Your review was published",
    );
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { reviews: { mode: "custom" } } };
    expect(sqlOf(COMMERCE, custom).trim()).toBe("");
    const [contract] = customContracts(["reviews"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual([
      "submit_review",
      "list_reviews",
      "review_summary",
      "publish_review",
      "reject_review",
    ]);
  });
});
