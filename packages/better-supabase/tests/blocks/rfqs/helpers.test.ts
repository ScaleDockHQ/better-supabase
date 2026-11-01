import { describe, expect, it } from "vitest";

import { createRfqs } from "../../../src/blocks/rfqs/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";

const RFQ = {
  id: "r1",
  organizationId: "org-1",
  number: "RFQ-1",
  title: "Pallets",
  status: "closed",
  currency: "EUR",
  createdAt: AT,
  updatedAt: AT,
};

const quote = (id: string, total: string, complete: boolean) => ({
  quoteId: id,
  invitationId: `i-${id}`,
  supplierType: "company",
  supplierId: `c-${id}`,
  status: "submitted",
  total,
  complete,
  lowest: false,
});

function setup(quotes: readonly ReturnType<typeof quote>[]) {
  return fieldsTransport({
    compare_rfq: () => ({ rfqId: "r1", currency: "EUR", lines: [], quotes }),
    award_rfq: () => ({ ...RFQ, status: "awarded" }),
  });
}

describe("rfqs helpers", () => {
  it("awardBest awards the cheapest quote that prices every line", async () => {
    const t = setup([
      quote("q-partial", "900", false),
      quote("q-best", "1200", true),
      quote("q-other", "1500", true),
    ]);

    const rfqs = createRfqs({ transport: t, tenant: "org-1" });

    const awarded = await rfqs
      .awardBest({ rfqId: "r1", location: "loc1" })
      .orThrow();

    expect(awarded.status).toBe("awarded");
    expect(t.calls[1]).toEqual([
      "award_rfq",
      { rfq_id: "r1", quote_id: "q-best", location: "loc1" },
    ]);
  });

  it("awardBest fails without a complete quote and awards nothing", async () => {
    const t = setup([quote("q-partial", "900", false)]);
    const rfqs = createRfqs({ transport: t, tenant: "org-1" });
    const awarded = await rfqs.awardBest({ rfqId: "r1" });

    expect(awarded.ok ? undefined : awarded.error).toMatchObject({
      hint: "RFQ_NO_COMPLETE_QUOTE",
    });

    expect(t.calls.map(([fn]) => fn)).toEqual(["compare_rfq"]);
  });
});
