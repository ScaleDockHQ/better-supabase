import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createDeals } from "../../src/blocks/deals/index.ts";
import { createForecasts } from "../../src/blocks/forecasts/index.ts";
import { money } from "../../src/commerce/money.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();
const eur = (amount: bigint) => money(amount, "EUR");

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "subjects",
  "state-machine",
  "rank",
  "contacts",
  "pipelines",
  "deals",
  "forecasts",
];

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["contacts", "deals"], {}),
};

describe.skipIf(!live)("forecasts", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("snapshots the forecast call and compares two snapshots", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: rep });
      const transport = sqlTransport(s.sql);
      const deals = createDeals({ transport });
      const forecasts = createForecasts({ transport });
      const today = Temporal.Now.plainDateISO();

      const period = {
        since: today.subtract({ days: 30 }),
        until: today.add({ days: 60 }),
        currency: "EUR",
        target: eur(2_000_000n),
      };

      await s.as(rep);

      const big = await deals
        .create(org, {
          name: "Big deal",
          closeOn: today.add({ days: 10 }),
          amount: eur(1_000_000n),
          forecast: "commit",
        })
        .orThrow();

      const small = await deals
        .create(org, {
          name: "Small deal",
          closeOn: today.add({ days: 20 }),
          amount: eur(500_000n),
          forecast: "pipeline",
        })
        .orThrow();

      const refused = await forecasts.snapshot(org, period);

      expect(refused.ok ? "ok" : refused.error.hint).toBe("FORECAST_FORBIDDEN");

      await s.as(owner);
      const first = await forecasts.snapshot(org, period).orThrow();

      expect(first).toMatchObject({ dealCount: 2, target: eur(2_000_000n) });
      expect(first.totals).toMatchObject({
        commit: eur(1_000_000n),
        pipeline: eur(500_000n),
        gap: eur(1_000_000n),
      });

      await s.as(rep);
      await deals.win(big.id, "Signed").orThrow();
      await deals
        .update([{ dealId: small.id, field: "amount", value: eur(750_000n) }])
        .orThrow();

      await s.as(owner);
      const second = await forecasts.snapshot(org, period).orThrow();

      expect(second.totals.won).toEqual(eur(1_000_000n));

      const changes = await forecasts.changes(first.id, second.id).orThrow();
      const byDeal = new Map(changes.deals.map((deal) => [deal.dealId, deal]));

      expect(byDeal.get(big.id)?.change).toBe("won");
      expect(byDeal.get(small.id)).toMatchObject({
        change: "changed",
        before: expect.objectContaining({ amount: eur(500_000n) }),
        after: expect.objectContaining({ amount: eur(750_000n) }),
      });

      await s.as(rep);
      const listed = await forecasts.list(org).orThrow();

      expect(listed.map((snapshot) => snapshot.id)).toEqual([
        second.id,
        first.id,
      ]);
      expect((await forecasts.get(first.id).orThrow()).deals).toHaveLength(2);

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 and type = 'forecast_snapshot.created'",
        [org],
      );

      expect(events).toHaveLength(2);
    } finally {
      await s.close();
    }
  });
});
