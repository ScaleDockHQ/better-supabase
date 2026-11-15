import { describe, expect, it } from "vitest";

import {
  asSeedRef,
  orderSeeds,
  resolveSeedValue,
  seedDate,
  seedRef,
  seedRefEntities,
  seedRefs,
} from "../../src/list/entity-seed.ts";

const resolver = {
  today: new Date("2026-11-15T10:00:00Z"),
  ref: (entity: string, name: string) => `${entity}:${name}`,
};

describe("seedRef and seedDate", () => {
  it("return plain objects a seed file can hold", () => {
    expect(seedRef("app.deals", "Hooli pilot")).toEqual({
      $seedRef: { entity: "app.deals", name: "Hooli pilot" },
    });

    expect(seedDate(-6)).toEqual({ $seedDate: -6 });
  });

  it("are found inside nested rows", () => {
    const row = {
      a: seedRef("app.deals", "One"),
      b: [
        { c: seedRef("app.pipelines", "Sales") },
        seedRef("app.deals", "Two"),
      ],
    };

    expect(seedRefs(row).map((ref) => ref.$seedRef.name)).toEqual([
      "One",
      "Sales",
      "Two",
    ]);

    expect(seedRefEntities(row)).toEqual(["app.deals", "app.pipelines"]);
  });

  it("reads an object with other keys as data", () => {
    expect(
      asSeedRef({ $seedRef: { entity: "a", name: "b" }, x: 1 }),
    ).toBeUndefined();

    expect(asSeedRef({ $seedRef: { entity: "a" } })).toBeUndefined();
    expect(asSeedRef("text")).toBeUndefined();
  });
});

describe("resolveSeedValue", () => {
  it("replaces refs with ids and dates with the day counted from today", () => {
    expect(
      resolveSeedValue(
        {
          stage: "won",
          deal: seedRef("app.deals", "Hooli pilot"),
          closeOn: seedDate(12),
          past: seedDate(-6),
          nested: [{ at: seedDate(0) }, 3, null],
        },
        resolver,
      ),
    ).toEqual({
      stage: "won",
      deal: "app.deals:Hooli pilot",
      closeOn: "2026-11-27",
      past: "2026-11-09",
      nested: [{ at: "2026-11-15" }, 3, null],
    });
  });

  it("returns a scalar as it is", () => {
    expect(resolveSeedValue("a", resolver)).toBe("a");
    expect(resolveSeedValue(false, resolver)).toBe(false);
  });
});

describe("orderSeeds", () => {
  const seed = (entity: string, dependsOn?: readonly string[]) => ({
    entity,
    dependsOn,
  });

  it("puts what a seed refers to first and keeps the rest in order", () => {
    const ordered = orderSeeds([
      seed("commissions.commission", ["app.deals"]),
      seed("risks.risk"),
      seed("app.deals", ["app.pipelines"]),
      seed("app.pipelines"),
    ]);

    expect(ordered.map((each) => each.entity)).toEqual([
      "app.pipelines",
      "app.deals",
      "commissions.commission",
      "risks.risk",
    ]);
  });

  it("stops on a cycle", () => {
    expect(() =>
      orderSeeds([seed("a.a", ["b.b"]), seed("b.b", ["a.a"])]),
    ).toThrow("a.a > b.b > a.a");
  });

  it("stops on a dependency that has no seed", () => {
    expect(() => orderSeeds([seed("a.a", ["b.b"])])).toThrow(
      "refers to b.b, which has no seed",
    );
  });
});
