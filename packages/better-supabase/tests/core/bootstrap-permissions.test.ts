import { describe, expect, it } from "vitest";

import {
  compactBootstrapPermissions,
  expandBootstrapPermissions,
} from "../../src/core/bootstrap-permissions.ts";

const tenants = (count: number, keys: number) =>
  Object.fromEntries(
    Array.from({ length: count }, (_, tenant) => [
      `00000000-0000-4000-8000-${String(tenant).padStart(12, "0")}`,
      Array.from(
        { length: keys },
        (_, key) => `resource_${String(key % 40)}.action_${String(key)}`,
      ).filter((_, key) => (key + tenant) % 3 !== 0),
    ]),
  );

describe("expandBootstrapPermissions", () => {
  it("reads the full form, with or without a form field", () => {
    const wire = {
      apiVersion: 1,
      tenants: { t1: ["a.read", "a.write"], t2: [] },
      platform: ["admin.all"],
    };

    expect(expandBootstrapPermissions(wire)).toEqual({
      apiVersion: 1,
      tenants: { t1: ["a.read", "a.write"], t2: [] },
      platform: ["admin.all"],
    });
    expect(expandBootstrapPermissions({ ...wire, form: "full" })).toEqual(
      expandBootstrapPermissions(wire),
    );
    expect(expandBootstrapPermissions({ apiVersion: 1, tenants: {} })).toEqual({
      apiVersion: 1,
      tenants: {},
      platform: [],
    });
  });

  it("round-trips the compact form, including the platform keys", () => {
    const full = {
      tenants: {
        t1: ["a.read", "b.read", "c.read"],
        t2: [
          "c.read",
          "d.read",
          "e.read",
          "f.read",
          "g.read",
          "h.read",
          "i.read",
        ],
      },
      platform: ["a.read", "i.read"],
    };

    const compact = compactBootstrapPermissions(full);

    expect(compact.form).toBe("compact");
    expect(compact.keys).toEqual([
      "a.read",
      "b.read",
      "c.read",
      "d.read",
      "e.read",
      "f.read",
      "g.read",
      "h.read",
      "i.read",
    ]);
    expect(expandBootstrapPermissions(compact)).toEqual({
      apiVersion: 1,
      ...full,
    });
  });

  it("reads a standard base64 bitset with padding, as Postgres encode() writes it", () => {
    // bits 0 and 2 of three keys: byte 0b00000101 = 0x05 = "BQ==".
    expect(
      expandBootstrapPermissions({
        apiVersion: 1,
        form: "compact",
        keys: ["a", "b", "c"],
        tenants: { t1: "BQ==" },
      }),
    ).toEqual({ apiVersion: 1, tenants: { t1: ["a", "c"] }, platform: [] });
  });

  it("fails closed on anything it does not understand", () => {
    const compact = (tenants: unknown, keys: unknown = ["a", "b", "c"]) => ({
      apiVersion: 1,
      form: "compact",
      keys,
      tenants,
    });

    for (const value of [
      undefined,
      null,
      "x",
      { tenants: {} },
      { apiVersion: 2, tenants: {} },
      { apiVersion: 1 },
      { apiVersion: 1, tenants: { t: "not a list" } },
      { apiVersion: 1, tenants: { t: [1] } },
      { apiVersion: 1, form: "other", tenants: {} },
      { apiVersion: 1, tenants: {}, platform: "x" },
      compact({ t: 5 }),
      compact({ t: "***" }),
      // A bit past the last key, and a byte past the key list.
      compact({ t: "CA==" }),
      compact({ t: "AAA=" }),
      compact({ t: "AA" }, "nope"),
    ]) {
      expect(expandBootstrapPermissions(value)).toBeUndefined();
    }
  });
});

describe("compact size", () => {
  it("is much smaller than the full form at 150 tenants and 300 keys", () => {
    const full = { apiVersion: 1, tenants: tenants(150, 300), platform: [] };
    const fullBytes = JSON.stringify(full).length;

    const compactBytes = JSON.stringify(
      compactBootstrapPermissions(full),
    ).length;

    // Recorded in ADR 0524.
    expect({ fullBytes, compactBytes }).toMatchInlineSnapshot(`
      {
        "compactBytes": 21314,
        "fullBytes": 737192,
      }
    `);
    expect(compactBytes).toBeLessThan(fullBytes / 5);
    const sorted = (keys: readonly string[]) => keys.toSorted();

    const expanded = expandBootstrapPermissions(
      compactBootstrapPermissions(full),
    );

    expect(
      Object.fromEntries(
        Object.entries(full.tenants).map(([tenant, keys]) => [
          tenant,
          sorted(keys),
        ]),
      ),
    ).toEqual(expanded?.tenants);
  });
});
