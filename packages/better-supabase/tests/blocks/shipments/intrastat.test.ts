import { describe, expect, it } from "vitest";

import type { BlockCall } from "../../../src/blocks/shared.ts";

import { shipmentsIntrastat } from "../../../src/blocks/shipments/intrastat.ts";
import { AsyncResult, ok } from "../../../src/core/result.ts";

const fake = (reply: unknown) => {
  const calls: { fn: string; args: Readonly<Record<string, unknown>> }[] = [];

  const call: BlockCall = (fn, args, then) => {
    calls.push({ fn, args });

    return AsyncResult.from(async () => ok(await then(reply)));
  };

  return {
    calls,
    client: shipmentsIntrastat(call, () => AsyncResult.ok("org")),
  };
};

describe("shipments intrastat client", () => {
  it("reads prepared lines and exceptions with their defaults", async () => {
    const { client, calls } = fake({
      period: "2026-10",
      lines: [
        {
          id: "l1",
          flow: "arrival",
          source: "manual",
          variantId: "v1",
          tradeCode: "8471",
          country: "DE",
          netMassKg: "1.5",
          quantity: "2",
          value: "1000",
          currency: "EUR",
        },
        { id: "l2" },
      ],
      exceptions: [
        { code: "INTRASTAT_TRADE_CODE_MISSING", lineId: "l2" },
        { code: "INTRASTAT_VALUE_MISSING", shipmentLineId: "s1" },
      ],
    });

    const prepared = await client.prepareIntrastat("2026-10").orThrow();

    expect(calls[0]?.args).toEqual({ tenant: "org", period: "2026-10" });
    expect(prepared.lines[0]).toMatchObject({
      flow: "arrival",
      source: "manual",
      value: "1000",
    });
    expect(prepared.lines[1]).toEqual({
      id: "l2",
      flow: "dispatch",
      source: "shipment",
      receiptLineId: null,
      supersedes: [],
      variantId: null,
      tradeCode: null,
      country: null,
      netMassKg: null,
      quantity: null,
      value: null,
      currency: null,
    });
    expect(prepared.exceptions).toEqual([
      {
        code: "INTRASTAT_TRADE_CODE_MISSING",
        lineId: "l2",
        shipmentLineId: null,
        receiptLineId: null,
      },
      {
        code: "INTRASTAT_VALUE_MISSING",
        lineId: null,
        shipmentLineId: "s1",
        receiptLineId: null,
      },
    ]);
  });

  it("reads receipt arrivals and what a manual line supersedes", async () => {
    const { client } = fake({
      period: "2026-10",
      superseded: [{ manualLineId: "m1", receiptLineId: "r1" }],
      lines: [
        {
          id: "m1",
          flow: "arrival",
          source: "manual",
          country: "DE",
          supersedes: ["r1"],
        },
        { id: "l3", flow: "arrival", source: "receipt", receiptLineId: "r2" },
      ],
      exceptions: [
        {
          code: "INTRASTAT_TRADE_CODE_MISSING",
          lineId: "l3",
          receiptLineId: "r2",
        },
      ],
    });

    const prepared = await client.prepareIntrastat("2026-10").orThrow();

    expect(prepared.lines[0]).toMatchObject({
      source: "manual",
      supersedes: ["r1"],
    });
    expect(prepared.lines[1]).toMatchObject({
      source: "receipt",
      receiptLineId: "r2",
    });
    expect(prepared.superseded).toEqual([
      { manualLineId: "m1", receiptLineId: "r1" },
    ]);
    expect(prepared.exceptions[0]).toMatchObject({ receiptLineId: "r2" });
  });

  it("saves a manual line as text amounts and deletes one", async () => {
    const saved = fake({ id: "l9" });

    const result = await saved.client
      .saveIntrastatLine({
        period: "2026-10",
        flow: "arrival",
        country: "DE",
        netMassKg: 2.5,
        quantity: 3,
        value: 1200n,
      })
      .orThrow();

    expect(result).toEqual({ id: "l9" });
    expect(saved.calls[0]?.args).toMatchObject({
      tenant: "org",
      line: null,
      attrs: { netMassKg: "2.5", quantity: "3", value: "1200" },
    });

    const removed = fake(true);

    expect(await removed.client.deleteIntrastatLine("l9").orThrow()).toBe(true);
    expect(removed.calls[0]).toEqual({
      fn: "delete_intrastat_line",
      args: { line: "l9" },
    });
  });
});
