import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  coldPending,
  coldRecord,
  recordCold,
} from "../../src/core/cold-start.ts";

const KEY = Symbol.for("better-supabase.cold-start");

describe("cold start record", () => {
  beforeEach(() => {
    Reflect.deleteProperty(globalThis, KEY);
  });

  it("keeps the first duration of each step", () => {
    expect(coldPending("query")).toBe(true);

    recordCold("query", 80);
    recordCold("query", 5);

    expect(coldPending("query")).toBe(false);
    expect(coldRecord().timings.query).toBe(80);
  });

  it("calls onQuery once, when the first query lands", () => {
    const onQuery = vi.fn();
    coldRecord().onQuery = onQuery;

    recordCold("claims", 40);
    expect(onQuery).not.toHaveBeenCalled();

    recordCold("query", 70);
    recordCold("query", 9);
    expect(onQuery).toHaveBeenCalledOnce();
  });

  it("is one record for every copy of the module in a process", () => {
    recordCold("create", 2);

    const scope = globalThis as Record<symbol, unknown>;
    expect(scope[KEY]).toBe(coldRecord());
  });
});
