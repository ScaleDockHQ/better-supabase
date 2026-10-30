import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { TestUser } from "./block-session.ts";

import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

interface Allocation {
  readonly lineId: string;
  readonly quantity: string;
  readonly allocated: string;
  readonly backordered: string;
  readonly status: string;
}

describe.skipIf(!live)("quote stock holds in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let owner: TestUser;
  let tenant: string;
  let tee: string;

  const call = <T>(sql: string, params: unknown[] = []): Promise<T> =>
    session.value<T>(sql, params);

  const quote = async (quantity: number): Promise<string> =>
    (
      await call<{ id: string }>(
        "better_supabase.create_quote($1, $2::jsonb, $3::jsonb)",
        [
          tenant,
          JSON.stringify({ title: "Tees", currency: "EUR" }),
          JSON.stringify([
            {
              description: "Tee",
              quantity,
              unitAmount: "1000",
              product: { type: "product_variant", id: tee },
            },
            { description: "Printing", quantity: 1, unitAmount: "500" },
          ]),
        ],
      )
    ).id;

  const versions = async (id: string): Promise<string[]> =>
    (
      await session.rows<{ id: string }>(
        "select id from better_supabase.quote_versions where quote_id = $1 order by revision",
        [id],
      )
    ).map((row) => row.id);

  const holds = (version: string): Promise<Allocation[]> =>
    call<Allocation[]>(
      "better_supabase.list_allocations($1, 'quote_version', $2)",
      [tenant, version],
    );

  const reserved = async (): Promise<number> => {
    const [row] = await session.rows<{ reserved: number }>(
      "select coalesce(sum(reserved), 0)::float8 as reserved from better_supabase.stock_levels where variant_id = $1",
      [tee],
    );

    return row?.reserved ?? 0;
  };

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install(
      [
        "organizations",
        "outbox",
        "subjects",
        "catalog",
        "inventory",
        "quotes",
        "orders",
      ],
      { modules: { quotes: { options: { holds: true } } } },
    );
    owner = await session.user("holds-owner");
    tenant = await session.organization(owner);
    await session.as(owner);

    const warehouse = await call<{ id: string }>(
      "better_supabase.save_location($1, null, 'WH-1', 'WH-1', 'warehouse')",
      [tenant],
    );

    const product = await call<{ id: string }>(
      "better_supabase.save_product($1, null, 'TEE', null, null, 'physical')",
      [tenant],
    );

    tee = (
      await call<{ id: string }>(
        "better_supabase.save_variant($1, null, 'TEE', '{}'::uuid[], null, null, null, true, false)",
        [product.id],
      )
    ).id;
    await call("better_supabase.adjust_stock($1, $2, 5, 'receipt', null)", [
      tee,
      warehouse.id,
    ]);
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("holds a sent version's catalog lines and releases them on revise and withdraw", async () => {
    await session.as(owner);
    const id = await quote(3);
    await call("better_supabase.send_quote($1)", [id]);
    const [first = ""] = await versions(id);

    expect(await holds(first)).toMatchObject([
      { quantity: "3.000000", allocated: "3.000000", status: "open" },
    ]);
    expect(await reserved()).toBe(3);

    await call("better_supabase.revise_quote($1)", [id]);
    expect((await holds(first))[0]?.status).toBe("released");
    expect(await reserved()).toBe(0);

    await call("better_supabase.send_quote($1)", [id]);
    const [, second = ""] = await versions(id);
    expect((await holds(second))[0]?.status).toBe("open");
    expect(await holds(first)).toHaveLength(1);

    await call("better_supabase.withdraw_quote($1)", [id]);
    expect((await holds(second))[0]?.status).toBe("released");
    expect(await reserved()).toBe(0);
  });

  it("hands the holds to the order made from the accepted quote", async () => {
    await session.as(owner);
    const id = await quote(4);
    await call("better_supabase.send_quote($1)", [id]);
    const [version = ""] = await versions(id);

    await call("better_supabase.decide_quote($1, 'accepted', null, 'Ana')", [
      id,
    ]);
    expect((await holds(version))[0]?.status).toBe("open");

    const order = await call<{ id: string }>(
      "better_supabase.order_from_quote($1)",
      [id],
    );

    expect((await holds(version))[0]?.status).toBe("released");
    expect(
      await call<Allocation[]>(
        "better_supabase.list_allocations($1, 'order', $2)",
        [tenant, order.id],
      ),
    ).toMatchObject([{ allocated: "4.000000", status: "open" }]);
  });

  it("backorders what isn't in stock and releases the holds of a quote that expires", async () => {
    await session.as(owner);
    const id = await quote(7);
    await call("better_supabase.send_quote($1)", [id]);
    const [version = ""] = await versions(id);

    expect(await holds(version)).toMatchObject([
      { allocated: "1.000000", backordered: "6.000000", status: "open" },
    ]);

    await session.service();
    await session.rows(
      "update better_supabase.quotes set valid_until = current_date - 1 where id = $1",
      [id],
    );
    await call("better_supabase.expire_quotes()");
    await session.as(owner);
    expect((await holds(version))[0]?.status).toBe("released");
  });
});
