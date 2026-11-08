import { afterEach, describe, expect, it, vi } from "vitest";

import type { BlockEvent } from "../../src/core/block-events.ts";
import type { AnyPlugin } from "../../src/core/plugin.ts";

import { isSqlType } from "../../src/config/sql-type.ts";
import { blockEventAttributes } from "../../src/core/block-events.ts";
import { tenantFrom } from "../../src/core/claims.ts";
import { nextCronRun } from "../../src/core/cron.ts";
import { keptPlugins } from "../../src/core/define-plugins.ts";
import { EventHub } from "../../src/core/events.ts";
import { jsonResponse } from "../../src/core/json.ts";
import { silentLogger, consoleLogger } from "../../src/core/logger.ts";
import { grainDivides } from "../../src/core/metric-definition.ts";
import { shareStructure } from "../../src/core/share.ts";
import { boundedTtlCache } from "../../src/core/ttl-cache.ts";
import { corsConfig } from "../../src/server/cors.ts";

afterEach(() => {
  vi.restoreAllMocks();
});

describe("consoleLogger", () => {
  it("prefixes the message and passes the fields when there are some", () => {
    const warn = vi.spyOn(console, "warn").mockReturnValue(undefined);
    consoleLogger.warn("slow", { ms: 5 });
    consoleLogger.warn("plain");
    expect(warn).toHaveBeenNthCalledWith(1, "better-supabase: slow", { ms: 5 });
    expect(warn).toHaveBeenNthCalledWith(2, "better-supabase: plain");
  });
});

describe("shareStructure on values that cannot match", () => {
  it("returns next for a changed type, null or another prototype", () => {
    const next = { a: 1 };
    expect(shareStructure(1, next)).toBe(next);
    expect(shareStructure(null, next)).toBe(next);
    expect(shareStructure(next, null)).toBeNull();
    expect(shareStructure([1], { a: 1 })).toEqual({ a: 1 });
  });

  it("returns prev for equal dates and next for different ones", () => {
    const prev = new Date("2026-01-01T00:00:00Z");
    expect(shareStructure(prev, new Date("2026-01-01T00:00:00Z"))).toBe(prev);
    const later = new Date("2026-01-02T00:00:00Z");
    expect(shareStructure(prev, later)).toBe(later);
  });
});

describe("keptPlugins", () => {
  it("says none are installed when the list is empty", () => {
    expect(() => keptPlugins([], ["audit"])).toThrow(/Installed: none/u);
  });
});

describe("shareStructure on arrays without ids", () => {
  it("matches the items by position", () => {
    const prev = [1, 2, 3];
    const next = [1, 2, 4];
    const shared = shareStructure(prev, next);
    expect(shared).toEqual([1, 2, 4]);
    expect(shareStructure(prev, [1, 2, 3])).toBe(prev);
  });
});

describe("nextCronRun", () => {
  it("skips the minute it is asked after", () => {
    const after = Temporal.Instant.from("2026-01-01T09:00:00Z");

    expect(nextCronRun("0 9 * * *", "UTC", after).toString()).toBe(
      "2026-01-02T09:00:00Z",
    );
  });
});

describe("grainDivides", () => {
  it.each([
    ["hour", "hour", true],
    ["hour", "month", true],
    ["day", "hour", false],
    ["day", "week", true],
    ["week", "week", true],
    ["week", "day", false],
    ["month", "month", true],
    ["month", "week", false],
  ] as const)("%s into %s is %s", (stored, grain, expected) => {
    expect(grainDivides(stored, grain)).toBe(expected);
  });
});

describe("small branches", () => {
  it("emits to nobody without handlers", () => {
    const hub = new EventHub(silentLogger);
    // SAFETY: the payload is never read, since nothing listens.
    expect(() => {
      hub.emit("block", {} as never);
    }).not.toThrow();
  });

  it("sets the JSON content type by default", () => {
    expect(jsonResponse({ a: 1 }).headers.get("content-type")).toBe(
      "application/json",
    );
  });

  it("expires entries against Date.now without a clock option", () => {
    const cache = boundedTtlCache<string, number>({ max: 2 });
    cache.set("a", 1, Date.now() + 60_000);
    expect(cache.get("a")).toBe(1);
    cache.set("b", 2, Date.now() - 1);
    expect(cache.get("b")).toBeUndefined();
  });

  it("reads the tenant from a claim path when the context has none", () => {
    expect(tenantFrom({ claims: { org: "t1" } }, ["missing", "org"])).toBe(
      "t1",
    );
  });

  it("names the tenant and actor of a block event", () => {
    const event = {
      type: "x.created",
      tenant: "t1",
      actorId: "u1",
      data: {},
    } as unknown as BlockEvent;

    expect(blockEventAttributes(event)).toMatchObject({
      "better_supabase.tenant": "t1",
      "better_supabase.actor.id": "u1",
    });
  });

  it("reuses a kept plugin list for the same names", () => {
    const plugins = [{ name: "audit" }] as unknown as readonly AnyPlugin[];
    const first = keptPlugins(plugins, ["audit"]);
    expect(keptPlugins(plugins, ["audit"])).toBe(first);
  });
});

describe("more small branches", () => {
  it("copies a list of allowed origins", () => {
    expect(
      corsConfig({ origin: ["https://a.test", "https://b.test"] }).origin,
    ).toEqual(["https://a.test", "https://b.test"]);
    expect(corsConfig({ origin: "https://a.test" }).origin).toBe(
      "https://a.test",
    );
  });

  it("refuses a character a quoted default may not hold", () => {
    expect(isSqlType("text default '\u0000'")).toBe(false);
    expect(isSqlType("text default 'a:b'")).toBe(true);
  });
});
