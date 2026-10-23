import { beforeAll, describe, expect, expectTypeOf, it } from "vitest";

import type {
  JsonPathEngine,
  Overlay10,
  Overlay11,
  Overlay12,
  OverlayVersion,
} from "../../src/spec/index.ts";

import {
  applyOverlay,
  loadJsonPath,
  overlayFromDiff,
} from "../../src/spec/index.ts";

let jsonpath: JsonPathEngine;

beforeAll(async () => {
  jsonpath = await loadJsonPath();
});

const base = {
  openapi: "3.1.2",
  info: { title: "CRM", version: "1.0.0", "x-old": true },
  tags: [{ name: "customers" }],
  servers: [{ url: "https://a.example" }, { url: "https://b.example" }],
  paths: {
    "/customers": {
      get: {
        operationId: "listCustomers",
        summary: "List",
        tags: ["customers"],
        parameters: [
          { name: "limit", in: "query" },
          { name: "cursor", in: "query" },
        ],
        security: [{ bearer: [] }],
      },
    },
    "/orders": { get: { operationId: "listOrders", deprecated: false } },
  },
  "x-matrix": [
    [1, 2],
    [3, 4],
  ],
};

const enriched = {
  openapi: "3.1.2",
  info: {
    title: "CRM API",
    version: "1.0.0",
    description: "Customers and orders",
  },
  tags: [{ name: "customers" }, { name: "orders" }],
  servers: [
    { url: "https://a.example" },
    { url: "https://c.example", name: "c" },
  ],
  paths: {
    "/customers": {
      get: {
        operationId: "listCustomers",
        summary: "List customers",
        tags: "customers",
        parameters: [{ name: "limit", in: "query" }],
        security: { bearer: [] },
        "x-better-supabase-table": "customers",
      },
    },
    "/orders": { get: { operationId: "listOrders", deprecated: true } },
    "/orders/{id}": { get: { operationId: "getOrder" } },
  },
  "x-matrix": [
    [1, 2],
    [3, 5],
  ],
};

const versions: readonly OverlayVersion[] = ["1.0.0", "1.1.0", "1.2.0"];

describe("overlayFromDiff", () => {
  it.each(versions)("round-trips base into enriched (%s)", (version) => {
    const overlay = overlayFromDiff(base, enriched, { version });
    expect(overlay.overlay).toBe(version);

    const { document, diagnostics } = applyOverlay(base, overlay, { jsonpath });

    expect(diagnostics).toEqual([]);
    expect(document).toEqual(enriched);
  });

  it("uses stable-key targets and one update per object", () => {
    const overlay = overlayFromDiff(base, enriched);
    expectTypeOf(overlay).toEqualTypeOf<Overlay11>();
    expect(overlay.info).toEqual({
      title: "better-supabase changes",
      version: "1.0.0",
    });
    const targets = overlay.actions.map((a) => a.target);
    expect(targets).toContain("$.paths['/orders'].get.deprecated");
    expect(targets).toContain("$.paths['/customers'].get");
    expect(targets).toContain("$.info['x-old']");
    expect(overlay.actions).toContainEqual({
      target: "$.paths",
      update: { "/orders/{id}": { get: { operationId: "getOrder" } } },
    });
    expect(overlay.actions).toContainEqual({
      target: "$.tags",
      update: [{ name: "orders" }],
    });
    expect(overlay.actions).toContainEqual({
      target: "$.info.title",
      update: "CRM API",
    });
  });

  it("writes changed primitives as a remove and re-add in 1.0", () => {
    const overlay = overlayFromDiff(
      { a: { b: 1 } },
      { a: { b: 2 } },
      {
        version: "1.0.0",
        info: { title: "x", version: "2" },
        extends: "o.json",
      },
    );

    expectTypeOf(overlay).toEqualTypeOf<Overlay10>();
    expect(overlay).toEqual({
      overlay: "1.0.0",
      info: { title: "x", version: "2" },
      extends: "o.json",
      actions: [
        { target: "$.a.b", remove: true },
        { target: "$.a", update: { b: 2 } },
      ],
    });
  });

  it("is typed per version and deterministic", () => {
    const v12 = overlayFromDiff(base, enriched, { version: "1.2.0" });
    expectTypeOf(v12).toEqualTypeOf<Overlay12>();
    expect(JSON.stringify(overlayFromDiff(base, enriched))).toBe(
      JSON.stringify(overlayFromDiff(base, enriched)),
    );
  });

  it("quotes names that need bracket notation", () => {
    const overlay = overlayFromDiff(
      { "it's": { "a\\b\n\t\u0001": 1, $ref: 1 }, list: [{ k: 1 }] },
      { "it's": { "a\\b\n\t\u0001": 2, $ref: 1 }, list: [{ k: 2 }] },
    );

    expect(overlay.actions.map((a) => a.target)).toEqual([
      "$['it\\'s']['a\\\\b\\n\\t\\u0001']",
      "$.list[0].k",
    ]);

    const { document } = applyOverlay(
      { "it's": { "a\\b\n\t\u0001": 1, $ref: 1 }, list: [{ k: 1 }] },
      overlay,
      { jsonpath },
    );

    expect(document).toEqual({
      "it's": { "a\\b\n\t\u0001": 2, $ref: 1 },
      list: [{ k: 2 }],
    });
  });

  it("replaces arrays whose items changed kind or order", () => {
    const from = { a: [1, 2, 3], b: [[1]], c: [{ x: 1 }, 2] };
    const to = { a: [3, 2, 1], b: [[2]], c: [{ x: 2 }, 3] };
    const overlay = overlayFromDiff(from, to);
    expect(overlay.actions).toEqual([
      { target: "$.a", remove: true },
      { target: "$.b", remove: true },
      { target: "$.c", remove: true },
      { target: "$", update: to },
    ]);
    expect(applyOverlay(from, overlay, { jsonpath }).document).toEqual(to);
  });

  it("throws for non-object roots and equal documents", () => {
    expect(() => overlayFromDiff([], {})).toThrow("must be objects");
    expect(() => overlayFromDiff({ a: 1 }, { a: 1 })).toThrow(
      "nothing to write",
    );
  });
});
