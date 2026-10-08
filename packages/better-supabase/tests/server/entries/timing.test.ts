import { pipeline } from "@supabase/middleware";
import { describe, expect, it } from "vitest";

import { withBetterSupabase } from "../../../src/server/composite.ts";
import {
  DB_CALLS_HEADER,
  formatDbStats,
  parseDbStats,
  withDbStats,
  withServerTiming,
} from "../../../src/server/entries/timing.ts";
import { requestAs, server } from "../../fixtures/test-server.ts";

describe("db stats header", () => {
  it("round-trips calls, waves and time", () => {
    const value = formatDbStats({
      calls: 3,
      waves: 2,
      ms: 12,
      tables: [],
    });
    expect(value).toBe("3;2;12");
    expect(parseDbStats(value)).toEqual({ calls: 3, waves: 2, ms: 12 });
    expect(parseDbStats("x;1;2")).toBeUndefined();
    expect(parseDbStats("1;2")).toBeUndefined();
    expect(parseDbStats(null)).toBeUndefined();
  });
});

describe("withServerTiming", () => {
  it("adds the total and the handler's metrics", async () => {
    let clock = 0;
    const fetch = pipeline(
      [withServerTiming(() => (clock += 5))],
      async (_request, ctx) => {
        ctx.timing.add('db "main"', 2.25, 'reads "x"');
        await ctx.timing.measure("render", () => "html");
        return new Response("ok", { status: 201 });
      },
    );
    const response = await fetch(new Request("https://app.test/"));
    expect(response.status).toBe(201);
    expect(response.headers.get("server-timing")).toBe(
      'bs;dur=15.0, db__main_;dur=2.3;desc="reads x", render;dur=5.0',
    );
  });
});

describe("withDbStats", () => {
  it("adds the request's database totals after the handler", async () => {
    const fetch = pipeline(
      [withBetterSupabase(server, { allow: ["anon"] }), withDbStats()],
      async (_request, ctx) => Response.json(ctx.dbStats().calls),
    );
    const response = await fetch(await requestAs());
    expect(await response.json()).toBe(0);
    expect(response.headers.get(DB_CALLS_HEADER)).toBe("0;0;0");
    expect(response.headers.get("server-timing")).toContain("bs-db;dur=0.0");
  });

  it("writes a custom header", async () => {
    const fetch = pipeline(
      [
        withBetterSupabase(server, { allow: ["anon"] }),
        withDbStats({ header: "x-db" }),
      ],
      async () => new Response(null, { status: 204 }),
    );
    const response = await fetch(await requestAs());
    expect(response.headers.get("x-db")).toBe("0;0;0");
  });
});
