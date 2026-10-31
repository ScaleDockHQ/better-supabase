import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type {
  FundingClaimChannel,
  FundingClaimFormat,
} from "../../../src/blocks/funding/index.ts";
import type { Result } from "../../../src/core/result.ts";

import {
  createFunding,
  fundingAwardInputSchema,
  fundingBlock,
} from "../../../src/blocks/funding/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { fieldsTransport } from "../fields-transport.ts";

const day = (text: string): Temporal.PlainDate => Temporal.PlainDate.from(text);

const PRODUCT = {
  id: "p1",
  organizationId: "org-1",
  code: "H126",
  title: "Personal care",
  unit: "hour",
  rate: "7500",
  currency: "EUR",
  validFrom: "2026-01-01",
  validUntil: null,
};

const AWARD = {
  id: "w1",
  organizationId: "org-1",
  subjectType: "client",
  subjectId: "c1",
  funderId: "f1",
  productId: "p1",
  units: "8",
  period: "week",
  startsOn: "2026-10-01",
  endsOn: null,
  reference: "IND-1",
  status: "active",
  createdBy: "u1",
  fields: { indication: "VV4" },
};

const DELIVERY = {
  id: "d1",
  organizationId: "org-1",
  awardId: "w1",
  sourceType: "time_entry",
  sourceId: "t1",
  deliveredOn: "2026-10-05",
  units: 1.5,
  performerId: "u2",
  status: "registered",
  claimLineId: null,
  note: null,
};

const CLAIM = {
  id: "k1",
  organizationId: "org-1",
  funderId: "f1",
  number: "7",
  periodStart: "2026-10-01",
  periodEnd: "2026-10-31",
  format: "iwlz-aw319",
  status: "draft",
  externalRef: null,
  sentAt: null,
  payloadSha256: null,
  response: null,
  total: "11250",
  currency: "EUR",
  invoiceId: null,
};

const LINE = {
  id: "l1",
  claimId: "k1",
  awardId: "w1",
  productId: "p1",
  units: "1.5",
  amount: "11250",
  status: "pending",
  rejectionCode: null,
  award: {
    subjectType: "client",
    subjectId: "c1",
    reference: "IND-1",
    period: "week",
  },
  product: { code: "H126", title: "Personal care", unit: "hour", rate: "7500" },
  deliveries: [
    {
      id: "d1",
      deliveredOn: "2026-10-05",
      units: 1.5,
      sourceType: "time_entry",
      sourceId: "t1",
      performerId: null,
    },
  ],
};

const CLAIM_WITH_LINES = { ...CLAIM, lines: [LINE] };

const SENT = {
  ...CLAIM,
  status: "sent",
  externalRef: "vecozo-1",
  sentAt: "2026-11-01T09:00:00Z",
  payloadSha256: "a".repeat(64),
};

const format: FundingClaimFormat = {
  apiVersion: 1,
  key: "iwlz-aw319",
  render: (claim, lines) => ({
    body: `${claim.number}:${lines.length}`,
    filename: "claim.xml",
    contentType: "application/xml",
  }),
  parseResponse: (body) => ({
    lines: [{ lineId: body, status: "rejected", rejectionCode: "0233" }],
    raw: { message: "AW320" },
  }),
};

const channelOf = (
  overrides: Partial<FundingClaimChannel> = {},
): FundingClaimChannel => ({
  apiVersion: 1,
  key: "vecozo",
  send: () => Promise.resolve({ externalRef: "vecozo-1" }),
  poll: () => Promise.resolve("l1"),
  ...overrides,
});

describe("createFunding", () => {
  it("saves and lists products with their rate as money", async () => {
    const t = fieldsTransport({
      save_funding_product: () => PRODUCT,
      list_funding_products: () => [PRODUCT],
    });

    const funding = createFunding({ transport: t });

    const saved = await funding
      .saveProduct("org-1", {
        code: "H126",
        title: "Personal care",
        unit: "hour",
        rate: money(7500n, "EUR"),
        validFrom: day("2026-01-01"),
      })
      .orThrow();

    await funding.products("org-1", { includeExpired: true }).orThrow();
    await funding.products("org-1").orThrow();

    expect(saved.rate).toEqual(money(7500n, "EUR"));
    expect(saved.validFrom?.toString()).toBe("2026-01-01");
    expect(saved.validUntil).toBeUndefined();
    expect(t.calls[0]).toEqual([
      "save_funding_product",
      {
        tenant: "org-1",
        code: "H126",
        title: "Personal care",
        unit: "hour",
        rate: "7500",
        currency: "EUR",
        valid_from: "2026-01-01",
        valid_until: null,
        product_id: null,
      },
    ]);
    expect(t.calls[1]?.[1]).toEqual({ tenant: "org-1", include_expired: true });
  });

  it("creates, updates, ends and lists awards with checked fields", async () => {
    const t = fieldsTransport({
      save_funding_award: () => AWARD,
      end_funding_award: () => ({
        ...AWARD,
        status: "ended",
        endsOn: "2026-12-31",
      }),
      list_funding_awards: () => [{ ...AWARD, product: PRODUCT }],
      funding_award_usage: () => ({
        awardId: "w1",
        units: 8,
        period: "week",
        periods: [
          {
            start: "2026-09-28",
            end: "2026-10-04",
            awarded: 8,
            used: 9,
            over: 1,
            under: 0,
          },
          {
            start: "2026-10-05",
            end: null,
            awarded: 8,
            used: 0,
            over: 0,
            under: 8,
          },
        ],
      }),
    });

    const funding = createFunding({
      transport: t,
      fields: v.object({ indication: v.string() }),
    });

    const subject = { type: "client", id: "c1" };

    const created = await funding
      .createAward("org-1", subject, {
        funderId: "f1",
        productId: "p1",
        units: 8,
        period: "week",
        startsOn: day("2026-10-01"),
        reference: "IND-1",
        fields: { indication: "VV4" },
      })
      .orThrow();

    await funding
      .updateAward("org-1", subject, "w1", { units: 10, endsOn: null })
      .orThrow();

    const ended = await funding
      .endAward("w1", { endsOn: day("2026-12-31") })
      .orThrow();

    await funding.endAward("w1").orThrow();

    const [listed] = await funding
      .awards("org-1", { subject, includeEnded: true })
      .orThrow();

    await funding.awards("org-1").orThrow();
    const usage = await funding.usage("w1").orThrow();

    expect(created).toMatchObject({
      units: 8,
      period: "week",
      subject,
      fields: { indication: "VV4" },
    });
    expect(created.endsOn).toBeUndefined();
    expect(ended.endsOn?.toString()).toBe("2026-12-31");
    expect(listed?.product.code).toBe("H126");
    expect(usage.periods[0]).toMatchObject({ used: 9, over: 1 });
    expect(usage.periods[1]?.end).toBeUndefined();
    expect(t.calls[0]).toEqual([
      "save_funding_award",
      {
        tenant: "org-1",
        subject_type: "client",
        subject_id: "c1",
        attrs: {
          funderId: "f1",
          productId: "p1",
          units: 8,
          period: "week",
          reference: "IND-1",
          fields: { indication: "VV4" },
          startsOn: "2026-10-01",
        },
        award_id: null,
      },
    ]);
    expect(t.calls[1]?.[1]).toMatchObject({
      award_id: "w1",
      attrs: { units: 10, endsOn: null },
    });
    expect(t.calls[2]?.[1]).toEqual({
      award_id: "w1",
      ends_on: "2026-12-31",
      canceled: false,
    });
    expect(t.calls[4]?.[1]).toEqual({
      tenant: "org-1",
      subject_type: "client",
      subject_id: "c1",
      include_ended: true,
    });
  });

  it("answers not_found for the usage of an award it can't read", async () => {
    const funding = createFunding({
      transport: fieldsTransport({ funding_award_usage: () => null }),
    });

    const result = await funding.usage("w9");
    expect(result.ok ? undefined : result.error.hint).toBe(
      "FUNDING_AWARD_NOT_FOUND",
    );
  });

  it("registers, approves and lists deliveries", async () => {
    const t = fieldsTransport({
      register_funding_delivery: () => DELIVERY,
      register_funding_deliveries_from_time: () => ({
        registered: [DELIVERY],
        unmatched: [
          {
            entryId: "t9",
            subjectType: "client",
            subjectId: "c2",
            deliveredOn: "2026-10-06",
            reason: "no_award",
          },
        ],
      }),
      approve_funding_deliveries: () => 1,
      list_funding_deliveries: () => [{ ...DELIVERY, sourceId: null }],
    });

    const service = fieldsTransport({
      register_funding_deliveries_from_time: () => ({
        registered: [],
        unmatched: [],
      }),
    });

    const funding = createFunding({ transport: t, service });

    const delivery = await funding
      .registerDelivery("w1", {
        deliveredOn: day("2026-10-05"),
        units: 1.5,
        sourceType: "time_entry",
        sourceId: "t1",
        performerId: "u2",
      })
      .orThrow();

    await funding
      .registerDelivery("w1", { deliveredOn: day("2026-10-05"), units: 1 })
      .orThrow();

    const registration = await funding
      .registerFromTime("org-1", day("2026-10-01"), day("2026-10-31"))
      .orThrow();

    const changed = await funding
      .approveDeliveries(["d1"], { approved: false })
      .orThrow();

    await funding.approveDeliveries(["d1"]).orThrow();

    const [listed] = await funding
      .deliveries("org-1", {
        awardId: "w1",
        status: "approved",
        since: day("2026-10-01"),
        until: day("2026-10-31"),
        limit: 10,
      })
      .orThrow();

    await funding.deliveries("org-1").orThrow();

    expect(delivery).toMatchObject({ units: 1.5, sourceId: "t1" });
    expect(delivery.claimLineId).toBeUndefined();
    expect(registration).toEqual({ registered: [], unmatched: [] });
    expect(service.calls).toEqual([
      [
        "register_funding_deliveries_from_time",
        { tenant: "org-1", since: "2026-10-01", until: "2026-10-31" },
      ],
    ]);
    expect(changed).toBe(1);
    expect(listed?.sourceId).toBeUndefined();
    expect(t.calls[1]?.[1]).toEqual({
      award_id: "w1",
      delivered_on: "2026-10-05",
      units: 1,
      source_type: "manual",
      source_id: null,
      performer_id: null,
      note: null,
    });
    expect(t.calls[2]?.[1]).toEqual({ ids: ["d1"], approved: false });
    expect(t.calls[3]?.[1]).toEqual({ ids: ["d1"], approved: true });
    expect(t.calls[4]?.[1]).toEqual({
      tenant: "org-1",
      filter: {
        awardId: "w1",
        status: "approved",
        since: "2026-10-01",
        until: "2026-10-31",
        limit: 10,
      },
    });
    expect(t.calls[5]?.[1]).toEqual({ tenant: "org-1", filter: {} });
  });

  it("reads the unmatched time entries the service registration returns", async () => {
    const funding = createFunding({
      transport: fieldsTransport({
        register_funding_deliveries_from_time: () => ({
          registered: [DELIVERY],
          unmatched: [
            {
              entryId: "t9",
              subjectType: "client",
              subjectId: "c2",
              deliveredOn: "2026-10-06",
              reason: "several_awards",
            },
          ],
        }),
      }),
    });

    const registration = await funding
      .registerFromTime("org-1", day("2026-10-01"), day("2026-10-31"))
      .orThrow();

    expect(registration.registered[0]).toMatchObject({
      id: "d1",
      sourceType: "time_entry",
    });
    expect(registration.unmatched[0]).toMatchObject({
      entryId: "t9",
      subject: { type: "client", id: "c2" },
      reason: "several_awards",
    });
  });

  it("builds, reads, lists, marks, answers, deletes and invoices claims", async () => {
    const t = fieldsTransport({
      build_funding_claim: () => CLAIM_WITH_LINES,
      get_funding_claim: () => CLAIM_WITH_LINES,
      list_funding_claims: () => [CLAIM],
      mark_funding_claim_sent: () => SENT,
      record_funding_claim_response: () => ({
        ...SENT,
        status: "rejected",
        response: { message: "AW320" },
        lines: [{ ...LINE, status: "rejected", rejectionCode: "0233" }],
      }),
      delete_funding_claim: () => true,
      invoice_funding_claim: () => ({
        claim: { ...CLAIM, status: "accepted", invoiceId: "i1" },
        invoice: { id: "i1" },
      }),
    });

    const funding = createFunding({ transport: t });

    const built = await funding
      .buildClaim("org-1", {
        funderId: "f1",
        periodStart: day("2026-10-01"),
        periodEnd: day("2026-10-31"),
        format: "iwlz-aw319",
      })
      .orThrow();

    const read = await funding.claim("k1").orThrow();
    await funding
      .claims("org-1", { status: "draft", funderId: "f1" })
      .orThrow();
    await funding.claims("org-1").orThrow();

    const sent = await funding
      .markSent("k1", { externalRef: "vecozo-1" })
      .orThrow();

    await funding.markSent("k1").orThrow();

    const answered = await funding
      .recordResponse("k1", {
        lines: [{ lineId: "l1", status: "rejected", rejectionCode: "0233" }],
      })
      .orThrow();

    const deleted = await funding.deleteClaim("k1").orThrow();

    const invoiced = await funding
      .invoiceClaim("k1", { dueOn: "2026-12-01" })
      .orThrow();

    await funding.invoiceClaim("k1").orThrow();

    expect(built.total).toEqual(money(11_250n, "EUR"));
    expect(built.lines[0]).toMatchObject({
      units: 1.5,
      amount: money(11_250n, "EUR"),
      award: { subject: { type: "client", id: "c1" }, reference: "IND-1" },
      product: { rate: money(7500n, "EUR") },
    });
    expect(built.lines[0]?.deliveries[0]?.performerId).toBeUndefined();
    expect(read.id).toBe("k1");
    expect(sent.sentAt?.toString()).toBe("2026-11-01T09:00:00Z");
    expect(answered.response).toEqual({ message: "AW320" });
    expect(answered.lines[0]?.rejectionCode).toBe("0233");
    expect(deleted).toBe(true);
    expect(invoiced.claim.invoiceId).toBe("i1");
    expect(invoiced.invoice).toEqual({ id: "i1" });
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "org-1",
      funder_id: "f1",
      period_start: "2026-10-01",
      period_end: "2026-10-31",
      format: "iwlz-aw319",
    });
    expect(t.calls[3]?.[1]).toEqual({
      tenant: "org-1",
      status: null,
      funder_id: null,
    });
    expect(t.calls[5]?.[1]).toEqual({
      claim_id: "k1",
      external_ref: null,
      payload_sha256: null,
    });
    expect(t.calls[6]?.[1]).toEqual({
      claim_id: "k1",
      lines: [{ lineId: "l1", status: "rejected", rejectionCode: "0233" }],
      response: null,
    });
    expect(t.calls[9]?.[1]).toEqual({ claim_id: "k1", attrs: null });
  });

  it("sends a claim through its format and channel and records the hash", async () => {
    const t = fieldsTransport({
      get_funding_claim: () => CLAIM_WITH_LINES,
      mark_funding_claim_sent: () => SENT,
    });

    const seen: string[] = [];

    const funding = createFunding({
      transport: t,
      formats: [format],
      channel: channelOf({
        send: (rendered, context) => {
          seen.push(rendered.body, context.claim.id);

          return Promise.resolve({ externalRef: "vecozo-1" });
        },
      }),
    });

    const sent = await funding.send("k1").orThrow();
    const [, markArgs] = t.calls[1] ?? [];

    expect(sent.status).toBe("sent");
    expect(seen).toEqual(["7:1", "k1"]);
    expect(markArgs).toMatchObject({
      claim_id: "k1",
      external_ref: "vecozo-1",
    });
    expect(String(markArgs?.["payload_sha256"])).toMatch(/^[0-9a-f]{64}$/);
  });

  it("refuses a send without the claim's format or a channel, and wraps a failing channel", async () => {
    const t = fieldsTransport({ get_funding_claim: () => CLAIM_WITH_LINES });

    const hint = async (run: PromiseLike<Result<unknown>>) => {
      const result = await run;

      return result.ok ? undefined : result.error.hint;
    };

    expect(await hint(createFunding({ transport: t }).send("k1"))).toBe(
      "FUNDING_FORMAT_UNKNOWN",
    );
    expect(
      await hint(createFunding({ transport: t, formats: [format] }).send("k1")),
    ).toBe("FUNDING_NO_CHANNEL");
    expect(
      await hint(
        createFunding({
          transport: t,
          formats: [format],
          channel: channelOf({
            send: () => Promise.reject(new Error("VECOZO is down")),
          }),
        }).send("k1"),
      ),
    ).toBe("FUNDING_CHANNEL_FAILED");
  });

  it("polls a sent claim's answer and records it", async () => {
    const t = fieldsTransport({
      get_funding_claim: () => ({ ...SENT, lines: [LINE] }),
      record_funding_claim_response: () => ({
        ...SENT,
        status: "rejected",
        lines: [{ ...LINE, status: "rejected", rejectionCode: "0233" }],
      }),
    });

    const answered = await createFunding({
      transport: t,
      formats: [format],
      channel: channelOf(),
    })
      .poll("k1")
      .orThrow();

    expect(answered?.status).toBe("rejected");
    expect(t.calls[1]).toEqual([
      "record_funding_claim_response",
      {
        claim_id: "k1",
        lines: [{ lineId: "l1", status: "rejected", rejectionCode: "0233" }],
        response: { message: "AW320" },
      },
    ]);

    const waiting = await createFunding({
      transport: t,
      formats: [format],
      channel: channelOf({ poll: () => Promise.resolve(undefined) }),
    })
      .poll("k1")
      .orThrow();

    const noPoll: FundingClaimChannel = {
      apiVersion: 1,
      key: "vecozo",
      send: () => Promise.resolve({ externalRef: "vecozo-1" }),
    };

    const unpolled = await createFunding({
      transport: t,
      formats: [format],
      channel: noPoll,
    })
      .poll("k1")
      .orThrow();

    expect(waiting).toBeUndefined();
    expect(unpolled).toBeUndefined();
  });

  it("validates award input and ships its manifest", () => {
    const ok = fundingAwardInputSchema["~standard"].validate({
      funderId: "00000000-0000-4000-8000-000000000001",
      productId: "00000000-0000-4000-8000-000000000002",
      units: 8,
      period: "week",
      startsOn: day("2026-10-01"),
    }) as { issues?: unknown[] };

    const bad = fundingAwardInputSchema["~standard"].validate({
      units: 8,
      period: "year",
    }) as { issues?: unknown[] };

    expect(ok.issues).toBeUndefined();
    expect(bad.issues?.length).toBeGreaterThan(0);
    expect(fundingBlock.name).toBe("funding");
    expect(fundingBlock.category).toBe("commerce");
  });
});
