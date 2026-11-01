import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createContacts } from "../../src/blocks/contacts/index.ts";
import { createInventory } from "../../src/blocks/inventory/index.ts";
import { createRfqs } from "../../src/blocks/rfqs/index.ts";
import { money } from "../../src/commerce/money.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();
const eur = (amount: bigint) => money(amount, "EUR");

const MODULES = [
  "organizations",
  "outbox",
  "catalog",
  "contacts",
  "inventory",
  "rfqs",
];

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["contacts"], {}),
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("rfqs", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("collects quotes, compares them and awards one into a purchase order", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("buyer");
      await s.install(MODULES, layout);
      const org = await s.organization(owner);
      const transport = sqlTransport(s.sql);
      const parties = createContacts({ transport });
      const inventory = createInventory({ transport });
      const rfqs = createRfqs({ transport, tenant: org });

      await s.as(owner);

      const product = await s.value<{ id: string }>(
        "better_supabase.save_product($1, null, 'Bolts', null, null, 'physical')",
        [org],
      );

      const variant = await s.value<{ id: string }>(
        "better_supabase.save_variant($1, null, 'BOLT', '{}'::uuid[], null, null, null, true, false)",
        [product.id],
      );

      const dock = await inventory
        .saveLocation({
          organizationId: org,
          input: { code: "DOCK", name: "Dock" },
        })
        .orThrow();

      const cheap = await parties
        .saveCompany({ organizationId: org, input: { name: "Cheap bolts" } })
        .orThrow();

      const fast = await parties
        .saveCompany({ organizationId: org, input: { name: "Fast bolts" } })
        .orThrow();

      await parties
        .setSupplierStatus({ partyId: cheap.id, status: "approved" })
        .orThrow();
      await parties
        .setSupplierStatus({ partyId: fast.id, status: "approved" })
        .orThrow();

      const rfq = await rfqs
        .createRfq({
          input: { title: "Bolts", currency: "EUR" },
          lines: [{ description: "Bolt", quantity: 10, variantId: variant.id }],
        })
        .orThrow();

      const line = rfq.lines[0]!;

      const a = await rfqs
        .inviteSupplier({
          rfqId: rfq.id,
          supplier: { type: "company", id: cheap.id },
        })
        .orThrow();

      const b = await rfqs
        .inviteSupplier({
          rfqId: rfq.id,
          supplier: { type: "company", id: fast.id },
        })
        .orThrow();

      expect(
        await rfqs
          .recordQuote({
            rfqId: rfq.id,
            invitationId: a.id,
            lines: [{ lineId: line.id, unitAmount: eur(100n) }],
          })
          .then(hint),
      ).toBe("RFQ_STATUS");

      await rfqs.openRfq(rfq.id).orThrow();
      await rfqs
        .recordQuote({
          rfqId: rfq.id,
          invitationId: a.id,
          lines: [{ lineId: line.id, unitAmount: eur(100n) }],
        })
        .orThrow();

      const second = await rfqs
        .recordQuote({
          rfqId: rfq.id,
          invitationId: b.id,
          lines: [{ lineId: line.id, unitAmount: eur(120n), leadTimeDays: 2 }],
        })
        .orThrow();

      const comparison = await rfqs.compare(rfq.id).orThrow();
      expect(comparison.quotes).toHaveLength(2);
      expect(comparison.quotes[0]?.total.amount).toBe(1000n);

      await rfqs.closeRfq(rfq.id).orThrow();

      const awarded = await rfqs
        .award({ rfqId: rfq.id, quoteId: second.id, location: dock.id })
        .orThrow();

      expect(awarded.status).toBe("awarded");
      expect(awarded.purchaseOrderId).toBeDefined();
    } finally {
      await s.close();
    }
  });
});
