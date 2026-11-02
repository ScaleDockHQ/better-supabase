import "temporal-polyfill/global";
import { money } from "better-supabase/commerce";
import { testRouteOptimizer, testFieldPack } from "better-supabase/testing";
import { describe, expect, it } from "vitest";

import { rubricCycle } from "../src/appraisal-rubric.ts";
import { invoiceHtml } from "../src/document-templates.ts";
import { consultancyPack } from "../src/field-pack.ts";
import numbering from "../src/numbering-config.ts";
import { presetBlocks, presetBlocksConfig } from "../src/presets.ts";
import { planShift, westToEastOptimizer } from "../src/route-optimizer.ts";
import { taxOfOneLine } from "../src/tax.ts";
import { suggestWhere } from "../src/warehouse.ts";
import { cannedTransport } from "./helpers.ts";

describe("route optimizer", () => {
  it("passes the conformance block", async () => {
    const report = await testRouteOptimizer(westToEastOptimizer);

    expect(report.checks.length).toBeGreaterThan(0);
  });
});

describe("planShift", () => {
  it("orders the visits with the custom optimizer", async () => {
    const startsAt = Temporal.Instant.from("2026-11-02T08:00:00Z");

    const plan = await planShift(
      { startsAt, endsAt: startsAt.add({ hours: 8 }) },
      [
        {
          id: "east",
          point: { latitude: 52.37, longitude: 4.95 },
          durationMinutes: 30,
        },
        {
          id: "west",
          point: { latitude: 52.37, longitude: 4.75 },
          durationMinutes: 30,
        },
      ],
    );

    expect(plan.visits.map((visit) => visit.id)).toEqual(["west", "east"]);
  });
});

describe("field pack", () => {
  it("passes the conformance block", async () => {
    const report = await testFieldPack(consultancyPack);

    expect(report.checks.length).toBeGreaterThan(0);
  });
});

describe("presets", () => {
  it.each(["psa", "ats", "intranet"] as const)("%s resolves", (name) => {
    const resolved = presetBlocks(name);

    expect(resolved.conflicts).toEqual([]);
    expect(resolved.blocks.length).toBeGreaterThan(5);
    expect(Object.keys(presetBlocksConfig(name)).length).toBeGreaterThan(0);
  });
});

describe("numbering config", () => {
  it("scopes quotes per legal entity", () => {
    expect(JSON.stringify(numbering)).toContain("legal_entity_id");
  });
});

describe("tax", () => {
  it("computes the tax of a line", async () => {
    const t = cannedTransport({
      compute_document_tax: () => ({
        groups: [
          {
            taxCodeId: "c1",
            code: "VAT21",
            type: "sales",
            rateBps: 2100,
            net: "10000",
            tax: "2100",
            gross: "12100",
            discount: "0",
            showTax: true,
          },
        ],
        subtotal: "10000",
        taxTotal: "2100",
        total: "12100",
        showTaxAmount: true,
      }),
    });

    const result = await taxOfOneLine(t, "c1");

    expect(result.total).toEqual(money(12_100n, "EUR"));
  });
});

describe("rpc examples", () => {
  it("renders a document", async () => {
    const t = cannedTransport({ render_document: () => null });

    await invoiceHtml(t, "inv-1");
    expect(t.calls[0]?.[0]).toBe("render_document");
  });

  it("asks the warehouse for putaway and slotting", async () => {
    const t = cannedTransport({});

    await suggestWhere(t, { binId: "b", variantId: "v", locationId: "l" });
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "save_bin_slot",
      "save_putaway_rule",
      "suggest_putaway",
      "suggest_slotting",
    ]);
  });

  it("creates a rubric cycle", async () => {
    const t = cannedTransport({});

    await rubricCycle(t, "r1");
    expect(t.calls.length).toBeGreaterThan(0);
  });
});
