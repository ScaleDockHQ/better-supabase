import { describe, expect, it } from "vitest";

import {
  createRfqs,
  rfqInputSchema,
  rfqsBlock,
} from "../../../src/blocks/rfqs/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { temporal } from "../../../src/core/temporal-required.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";

const RFQ = {
  id: "r1",
  organizationId: "org-1",
  number: "RFQ-1",
  title: "Pallets",
  status: "draft",
  currency: "EUR",
  createdAt: AT,
  updatedAt: AT,
};

const QUOTE = {
  id: "q1",
  rfqId: "r1",
  invitationId: "i1",
  status: "submitted",
  currency: "EUR",
  total: "12500",
  revision: 1,
  validUntil: "2026-12-01",
  submittedAt: AT,
  updatedAt: AT,
  lines: [
    {
      id: "ql1",
      quoteId: "q1",
      lineId: "l1",
      unitAmount: "1250",
      leadTimeDays: 5,
    },
  ],
};

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createRfqs", () => {
  it("creates a request with its lines and reads it back", async () => {
    const t = fieldsTransport({
      create_rfq: () => ({
        ...RFQ,
        lines: [
          {
            id: "l1",
            rfqId: "r1",
            ordinal: 1,
            description: "Pallet",
            quantity: 10,
          },
        ],
        suppliers: [],
        quotes: [QUOTE],
      }),
    });

    const rfqs = createRfqs({ transport: t, tenant: "org-1" });

    const created = await rfqs
      .createRfq({
        input: { title: "Pallets", currency: "EUR" },
        lines: [{ description: "Pallet", quantity: 10 }],
      })
      .orThrow();

    expect(created.number).toBe("RFQ-1");
    expect(created.lines[0]).toMatchObject({ ordinal: 1, quantity: 10 });
    expect(created.quotes[0]?.total).toEqual(money(12_500n, "EUR"));
    expect(created.quotes[0]?.lines?.[0]?.unitAmount).toEqual(
      money(1250n, "EUR"),
    );
    expect(t.calls[0]).toEqual([
      "create_rfq",
      {
        tenant: "org-1",
        input: { title: "Pallets", currency: "EUR" },
        lines: [{ description: "Pallet", quantity: 10 }],
      },
    ]);
  });

  it("invites, opens and lists", async () => {
    const t = fieldsTransport({
      invite_rfq_supplier: () => ({
        id: "i1",
        rfqId: "r1",
        supplierType: "company",
        supplierId: "c1",
        status: "invited",
        invitedAt: AT,
      }),
      open_rfq: () => ({ ...RFQ, status: "open" }),
      list_rfqs: () => [RFQ],
    });

    const rfqs = createRfqs({ transport: t, tenant: "org-1" });

    const invited = await rfqs
      .inviteSupplier({ rfqId: "r1", supplier: { type: "company", id: "c1" } })
      .orThrow();

    const opened = await rfqs.openRfq("r1").orThrow();
    const listed = await rfqs.listRfqs({ status: "draft" }).orThrow();

    expect(invited.status).toBe("invited");
    expect(opened.status).toBe("open");
    expect(listed).toHaveLength(1);
    expect(t.calls[0]).toEqual([
      "invite_rfq_supplier",
      { rfq_id: "r1", supplier_type: "company", supplier_id: "c1" },
    ]);
    expect(t.calls[2]).toEqual([
      "list_rfqs",
      { tenant: "org-1", filters: { status: "draft" } },
    ]);
  });

  it("sends quote amounts as minor-unit text and decodes the quote", async () => {
    const t = fieldsTransport({
      record_rfq_quote: () => QUOTE,
      withdraw_rfq_quote: () => ({ ...QUOTE, status: "withdrawn" }),
    });

    const rfqs = createRfqs({ transport: t, tenant: "org-1" });

    const quote = await rfqs
      .recordQuote({
        rfqId: "r1",
        invitationId: "i1",
        lines: [
          { lineId: "l1", unitAmount: money(1250n, "EUR"), leadTimeDays: 5 },
        ],
        input: { validUntil: temporal().PlainDate.from("2026-12-01") },
      })
      .orThrow();

    const withdrawn = await rfqs.withdrawQuote("q1").orThrow();

    expect(quote.total).toEqual(money(12_500n, "EUR"));
    expect(quote.validUntil?.toString()).toBe("2026-12-01");
    expect(withdrawn.status).toBe("withdrawn");
    expect(t.calls[0]).toEqual([
      "record_rfq_quote",
      {
        rfq_id: "r1",
        invitation_id: "i1",
        input: { validUntil: "2026-12-01" },
        lines: [{ lineId: "l1", unitAmount: "1250", leadTimeDays: 5 }],
      },
    ]);
  });

  it("compares quotes and awards one", async () => {
    const t = fieldsTransport({
      compare_rfq: () => ({
        rfqId: "r1",
        currency: "EUR",
        lines: [
          {
            lineId: "l1",
            ordinal: 1,
            description: "Pallet",
            quantity: 10,
            offers: [
              {
                quoteId: "q1",
                invitationId: "i1",
                unitAmount: "1250",
                lineTotal: "12500",
                leadTimeDays: 5,
                lowest: true,
              },
            ],
          },
        ],
        quotes: [
          {
            quoteId: "q1",
            invitationId: "i1",
            supplierType: "company",
            supplierId: "c1",
            status: "submitted",
            total: "12500",
            complete: true,
            lowest: true,
          },
        ],
      }),
      award_rfq: () => ({
        ...RFQ,
        status: "awarded",
        awardedQuoteId: "q1",
        purchaseOrderId: "po1",
      }),
    });

    const rfqs = createRfqs({ transport: t, tenant: "org-1" });
    const comparison = await rfqs.compare("r1").orThrow();

    const awarded = await rfqs
      .award({ rfqId: "r1", quoteId: "q1", location: "loc1" })
      .orThrow();

    expect(comparison.lines[0]?.offers[0]).toMatchObject({
      lowest: true,
      lineTotal: money(12_500n, "EUR"),
    });
    expect(comparison.quotes[0]).toMatchObject({
      complete: true,
      lowest: true,
    });
    expect(awarded).toMatchObject({
      status: "awarded",
      awardedQuoteId: "q1",
      purchaseOrderId: "po1",
    });
    expect(t.calls[1]).toEqual([
      "award_rfq",
      { rfq_id: "r1", quote_id: "q1", location: "loc1" },
    ]);
  });

  it("closes and cancels", async () => {
    const t = fieldsTransport({
      close_rfq: () => ({ ...RFQ, status: "closed" }),
      cancel_rfq: () => ({ ...RFQ, status: "cancelled", cancelReason: "no" }),
    });

    const rfqs = createRfqs({ transport: t, tenant: "org-1" });

    expect((await rfqs.closeRfq("r1").orThrow()).status).toBe("closed");
    expect(
      (await rfqs.cancelRfq({ rfqId: "r1", reason: "no" }).orThrow())
        .cancelReason,
    ).toBe("no");
  });

  it("validates the request input and names the block", () => {
    expect(
      validate(rfqInputSchema, { title: "Pallets", currency: "EUR" }).issues,
    ).toBeUndefined();
    expect(
      validate(rfqInputSchema, { title: "", currency: "EUR" }).issues,
    ).toBeDefined();
    expect(rfqsBlock.name).toBe("rfqs");
  });
});
