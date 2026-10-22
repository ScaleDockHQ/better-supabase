import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createDeals } from "../../src/blocks/deals/index.ts";
import { createFieldHistory } from "../../src/blocks/field-history/index.ts";
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
  "field-history",
];

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["parties", "deals"], {}),
  modules: {
    "field-history": {
      on: { deal: { fields: ["amount", "forecast_category"] } },
    },
  },
};

describe.skipIf(!live)("field history", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("records the tracked columns a member changes", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      const stranger = await s.user("stranger");
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: rep });
      await s.organization(stranger);
      const transport = sqlTransport(s.sql);
      const deals = createDeals({ transport });
      const history = createFieldHistory({ transport });

      await s.as(rep);

      const deal = await deals
        .create(org, {
          name: "Growth plan",
          closeOn: Temporal.Now.plainDateISO().add({ days: 30 }),
          amount: eur(100_000n),
          forecast: "pipeline",
        })
        .orThrow();

      const subject = { type: "deal", id: deal.id };

      expect(await history.of(subject).orThrow()).toEqual([]);

      await deals
        .update([
          { dealId: deal.id, field: "amount", value: eur(150_000n) },
          { dealId: deal.id, field: "forecast", value: "commit" },
          { dealId: deal.id, field: "name", value: "Growth plan, 60 seats" },
        ])
        .orThrow();

      const changes = await history.of(subject).orThrow();

      expect(changes.map((change) => change.field).toSorted()).toEqual([
        "amount",
        "forecast_category",
      ]);
      expect(changes.find((change) => change.field === "amount")).toMatchObject(
        { before: 100_000, after: 150_000, changedBy: rep.id },
      );

      const amountOnly = await history
        .of(subject, { field: "amount" })
        .orThrow();

      expect(amountOnly).toHaveLength(1);

      const page = await history
        .of(subject, { before: amountOnly[0]?.id ?? "", limit: 5 })
        .orThrow();

      expect(page.every((change) => change.id !== amountOnly[0]?.id)).toBe(
        true,
      );

      await s.as(stranger);
      expect(await history.of(subject).orThrow()).toEqual([]);
    } finally {
      await s.close();
    }
  });
});
