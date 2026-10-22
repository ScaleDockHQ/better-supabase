import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";
import type { TestUser } from "./block-session.ts";

import { createReviews, sqlTransport } from "../../src/blocks/reviews/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

interface Review {
  readonly id: string;
  readonly status: string;
  readonly verified: boolean;
  readonly rating: number;
  readonly authorId: string | null;
  readonly mine: boolean;
}

interface Summary {
  readonly count: number;
  readonly average: number | null;
  readonly histogram: Record<string, number>;
}

const MODULES = [
  "organizations",
  "catalog",
  "inventory",
  "outbox",
  "numbering",
  "orders",
  "reviews",
] as const;

const layout = (reviews: object = {}): BlockSqlLayout => ({
  modules: {
    catalog: { options: { storefront: "public" } },
    numbering: {
      options: {
        entities: {
          order: { period: "none", format: "SO-{n:4}" },
          invoice: { period: "none", format: "INV-{n:5}" },
        },
      },
    },
    reviews: {
      options: {
        subjects: { ticket: { table: "public.tickets" } },
        ...reviews,
      },
    },
  },
});

const tickets = (s: BlockSession) =>
  s.client.query(
    "create table public.tickets (id uuid primary key default gen_random_uuid(), organization_id uuid not null)",
  );

/** An active product in `tenant`, created as `owner`. */
async function product(
  s: BlockSession,
  owner: TestUser,
  tenant: string,
  title: string,
): Promise<string> {
  await s.as(owner);

  const saved = await s.value<{ id: string }>(
    "better_supabase.save_product($1, null, $2, null, null, 'physical')",
    [tenant, title],
  );

  await s.value("better_supabase.set_product_status($1, 'active')", [saved.id]);

  return saved.id;
}

/** A paid order for `productId` placed by `customer`, written directly. */
async function paidOrder(
  s: BlockSession,
  tenant: string,
  customer: TestUser,
  productId: string,
  paid = true,
): Promise<void> {
  await s.service();

  const [order] = await s.rows<{ id: string }>(
    `insert into better_supabase.orders (tenant_id, number, sequence, customer_id, currency, paid_at)
     values ($1, $2, 1, $3, 'EUR', $4) returning id`,
    [
      tenant,
      `SO-${crypto.randomUUID().slice(0, 6)}`,
      customer.id,
      paid ? new Date() : null,
    ],
  );

  await s.rows(
    `insert into better_supabase.order_lines (tenant_id, order_id, product_id, sku, title, quantity)
     values ($1, $2, $3, 'SKU', 'Item', 1)`,
    [tenant, order!.id, productId],
  );
}

describe.skipIf(!live)("reviews module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("moderates storefront product reviews and keeps the aggregate public", async () => {
    const s = await BlockSession.open(pool);

    try {
      await tickets(s);
      await s.install(MODULES, layout());
      const owner = await s.user("owner");
      const buyer = await s.user("buyer");
      const browser = await s.user("browser");
      const tenant = await s.organization(owner);
      const lamp = await product(s, owner, tenant, "Lamp");

      await s.as(buyer);
      expect(
        await s.hint("better_supabase.submit_review($1, 'product', $2, 5)", [
          tenant,
          lamp,
        ]),
      ).toBe("REVIEW_FORBIDDEN");

      await s.as(owner);
      await s.value("better_supabase.publish_storefront($1, true)", [tenant]);
      await paidOrder(s, tenant, buyer, lamp);

      await s.as(buyer);

      const first = await s.value<Review>(
        "better_supabase.submit_review($1, 'product', $2, 4, 'Bright', 'Good lamp')",
        [tenant, lamp],
      );

      expect(first).toMatchObject({
        status: "pending",
        verified: true,
        rating: 4,
        mine: true,
      });
      expect(
        await s.hint("better_supabase.submit_review($1, 'product', $2, 6)", [
          tenant,
          lamp,
        ]),
      ).toBe("REVIEW_INVALID");

      await s.as(browser);

      const unverified = await s.value<Review>(
        "better_supabase.submit_review($1, 'product', $2, 2)",
        [tenant, lamp],
      );

      expect(unverified.verified).toBe(false);
      expect(
        await s.hint("better_supabase.publish_review($1)", [unverified.id]),
      ).toBe("REVIEW_FORBIDDEN");

      await s.as("anon");
      expect(
        await s.value<Review[]>(
          "better_supabase.list_reviews($1, 'product', $2)",
          [tenant, lamp],
        ),
      ).toEqual([]);

      await s.as(owner);
      expect(
        await s.value<Review[]>("better_supabase.review_queue($1)", [tenant]),
      ).toHaveLength(2);
      await s.value("better_supabase.publish_review($1)", [first.id]);
      await s.value("better_supabase.reject_review($1, 'Off topic')", [
        unverified.id,
      ]);

      await s.as("anon");

      const listed = await s.value<Review[]>(
        "better_supabase.list_reviews($1, 'product', $2)",
        [tenant, lamp],
      );

      expect(listed.map((review) => review.id)).toEqual([first.id]);
      expect(listed[0]?.authorId).toBeNull();

      const summary = await s.value<Record<string, Summary>>(
        "better_supabase.review_summary($1, 'product', $2)",
        [tenant, [lamp]],
      );

      expect(summary[lamp]).toMatchObject({
        count: 1,
        average: 4,
        histogram: { "4": 1 },
      });

      await s.as(buyer);
      await s.value(
        "better_supabase.submit_review($1, 'product', $2, 1, 'Broke')",
        [tenant, lamp],
      );
      await s.as("anon");
      expect(
        await s.value<Record<string, Summary>>(
          "better_supabase.review_summary($1, 'product', $2)",
          [tenant, [lamp]],
        ),
      ).toEqual({});

      await s.as(buyer);
      expect(
        await s.value<boolean>("better_supabase.delete_review($1)", [first.id]),
      ).toBe(true);
      expect(
        await s.value<Review | null>(
          "better_supabase.my_review($1, 'product', $2)",
          [tenant, lamp],
        ),
      ).toBeNull();
    } finally {
      await s.close();
    }
  });

  it("publishes at once under post-moderation and requires a purchase when asked", async () => {
    const s = await BlockSession.open(pool);

    try {
      await tickets(s);
      await s.install(
        MODULES,
        layout({ moderation: "post", requirePurchase: true }),
      );
      const owner = await s.user("owner");
      const buyer = await s.user("buyer");
      const browser = await s.user("browser");
      const tenant = await s.organization(owner);
      const mug = await product(s, owner, tenant, "Mug");

      await s.value("better_supabase.publish_storefront($1, true)", [tenant]);
      await paidOrder(s, tenant, buyer, mug);
      await paidOrder(s, tenant, browser, mug, false);

      await s.as(browser);
      expect(
        await s.hint("better_supabase.submit_review($1, 'product', $2, 5)", [
          tenant,
          mug,
        ]),
      ).toBe("REVIEW_PURCHASE_REQUIRED");

      await s.as(buyer);
      expect(
        await s.value<Review>(
          "better_supabase.submit_review($1, 'product', $2, 5)",
          [tenant, mug],
        ),
      ).toMatchObject({ status: "published", verified: true });

      await s.as(owner);

      const replied = await s.value<{ reply: string }>(
        "better_supabase.reply_to_review((select id from better_supabase.reviews where subject_id = $1::text), 'Thanks')",
        [mug],
      );

      expect(replied.reply).toBe("Thanks");

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 and type like 'review.%' order by position",
        [tenant],
      );

      expect(events.map((event) => event.type)).toEqual([
        "review.submitted",
        "review.published",
        "review.replied",
      ]);
    } finally {
      await s.close();
    }
  });

  it("reviews a registered subject only inside its organization", async () => {
    const s = await BlockSession.open(pool);

    try {
      await tickets(s);
      await s.install(MODULES, layout());
      const owner = await s.user("owner");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const tenant = await s.organization(owner, { member });

      await s.service();

      const [ticket] = await s.rows<{ id: string }>(
        "insert into public.tickets (organization_id) values ($1) returning id",
        [tenant],
      );

      await s.as(outsider);
      expect(
        await s.hint("better_supabase.submit_review($1, 'ticket', $2, 3)", [
          tenant,
          ticket!.id,
        ]),
      ).toBe("REVIEW_FORBIDDEN");

      await s.as(member);
      const reviews = createReviews({ transport: sqlTransport(s.sql) });

      const submitted = await reviews
        .submit(tenant, "ticket", ticket!.id, { rating: 3 })
        .orThrow();

      expect(submitted).toMatchObject({ status: "pending", verified: false });
      expect(
        (await reviews.mine(tenant, "ticket", ticket!.id).orThrow())?.rating,
      ).toBe(3);
    } finally {
      await s.close();
    }
  });
});
