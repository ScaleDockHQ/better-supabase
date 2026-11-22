import { describe, expect, it } from "vitest";

import { createSupabase } from "../../../src/core/define.ts";
import { vercelMetrics } from "../../../src/otel/vercel/index.ts";
import { capturingClient } from "../../fixtures/client.ts";
import { schema } from "../../fixtures/generated-camel.ts";

type Call = readonly [string, number, Record<string, string> | undefined];

function recorder() {
  const calls: Call[] = [];

  return {
    calls,
    metric: (name: string, value: number, tags?: Record<string, string>) => {
      calls.push([name, value, tags]);
    },
  };
}

describe("vercelMetrics", () => {
  it("sends the duration of a query with its table, operation and outcome", async () => {
    const { calls, metric } = recorder();
    const betterSupabase = createSupabase(schema).use(vercelMetrics(metric));
    const { client } = capturingClient(() => ({ body: [{ id: "c1" }] }));

    await betterSupabase
      .connect(client)
      .customers.list({ where: { name: "secret value" } })
      .orThrow();

    expect(calls).toHaveLength(1);
    expect(calls[0]?.[0]).toBe("better_supabase.db.duration_ms");
    expect(calls[0]?.[1]).toBeGreaterThanOrEqual(0);
    expect(calls[0]?.[2]).toEqual({
      target: "customers",
      operation: "select",
      outcome: "ok",
    });
    expect(JSON.stringify(calls)).not.toContain("secret");
  });

  it("counts a failure by its kind before its duration", async () => {
    const { calls, metric } = recorder();

    const betterSupabase = createSupabase(schema).use(
      vercelMetrics(metric, { prefix: "crm.db", tags: { app: "crm" } }),
    );

    const { client } = capturingClient(() => ({
      status: 409,
      body: { code: "23505", message: "duplicate key value" },
    }));

    const result = await betterSupabase
      .connect(client)
      .customers.create({ organizationId: "o1", name: "A" });

    expect(result.error?.kind).toBe("conflict");
    expect(calls.map(([name]) => name)).toEqual([
      "crm.db.errors",
      "crm.db.duration_ms",
    ]);
    expect(calls[0]).toEqual([
      "crm.db.errors",
      1,
      {
        app: "crm",
        target: "customers",
        operation: "insert",
        kind: "conflict",
      },
    ]);
    expect(calls[1]?.[2]).toMatchObject({ outcome: "error" });
  });

  it("stops at the budget with one marker as its last call", async () => {
    const { calls, metric } = recorder();

    const betterSupabase = createSupabase(schema).use(
      vercelMetrics(metric, { maxCalls: 3 }),
    );

    const { client } = capturingClient();
    const db = betterSupabase.connect(client);

    for (let index = 0; index < 6; index += 1) {
      await db.customers.list().orThrow();
    }

    expect(calls.map(([name]) => name)).toEqual([
      "better_supabase.db.duration_ms",
      "better_supabase.db.duration_ms",
      "better_supabase.db.budget_exceeded",
    ]);
  });

  it("gives every connection its own budget", async () => {
    const { calls, metric } = recorder();

    const betterSupabase = createSupabase(schema).use(
      vercelMetrics(metric, { maxCalls: 2 }),
    );

    const { client } = capturingClient();

    for (let request = 0; request < 2; request += 1) {
      const db = betterSupabase.connect(client);
      await db.customers.list().orThrow();
      await db.customers.list().orThrow();
    }

    expect(calls.map(([name]) => name)).toEqual([
      "better_supabase.db.duration_ms",
      "better_supabase.db.budget_exceeded",
      "better_supabase.db.duration_ms",
      "better_supabase.db.budget_exceeded",
    ]);
  });

  it("keeps the result when metric throws, and stops calling it", async () => {
    let attempts = 0;

    const betterSupabase = createSupabase(schema).use(
      vercelMetrics(() => {
        attempts += 1;
        throw new Error("ipc closed");
      }),
    );

    const { client } = capturingClient(() => ({ body: [{ id: "c1" }] }));
    const db = betterSupabase.connect(client);

    const first = await db.customers.list().orThrow();
    await db.customers.list().orThrow();

    expect(first).toHaveLength(1);
    expect(attempts).toBe(1);
  });

  it("rethrows a rejection unchanged and counts it as an exception", async () => {
    const { calls, metric } = recorder();
    const boom = new Error("socket hang up");

    const wrapped = vercelMetrics(metric).wrapExecutor?.({
      name: "postgrest",
      execute: () => Promise.reject(boom),
      rpc: () => Promise.reject(boom),
    });

    await expect(
      wrapped?.rpc?.(
        "refresh_totals",
        {},
        { schema: "public", errorMappers: [] },
      ),
    ).rejects.toBe(boom);
    expect(calls.map(([name, , tags]) => [name, tags?.["kind"]])).toEqual([
      ["better_supabase.db.errors", "exception"],
      ["better_supabase.db.duration_ms", undefined],
    ]);
    expect(calls[0]?.[2]).toMatchObject({
      target: "refresh_totals",
      operation: "rpc",
    });
  });

  it("names upserts and counts, and measures rpc and batch outcomes", async () => {
    const { calls, metric } = recorder();
    const fail = { ok: false, error: { kind: "conflict" } };

    const wrapped = vercelMetrics(metric).wrapExecutor?.({
      name: "postgrest",
      execute: async () => ({ ok: true, data: [] }),
      rpc: async () => fail,
      batch: async (ops: readonly unknown[]) =>
        ops.length > 1
          ? [{ ok: true, data: [] }, fail]
          : [{ ok: true, data: [] }],
    } as never);

    const table = { name: "customers" };
    const context = { schema: "public", errorMappers: [] } as never;

    await wrapped?.execute(
      { kind: "insert", table, onConflict: { action: "update" } } as never,
      context,
    );
    await wrapped?.execute(
      { kind: "select", table, head: true } as never,
      context,
    );
    await wrapped?.execute({ kind: "delete", table } as never, context);
    await wrapped?.rpc?.("refresh_totals", {}, context);
    await wrapped?.batch?.([{}, {}] as never, context);
    await wrapped?.batch?.([{}] as never, context);

    const durations = calls
      .filter(([name]) => name.endsWith("duration_ms"))
      .map(([, , tags]) => [
        tags?.["target"],
        tags?.["operation"],
        tags?.["outcome"],
      ]);

    expect(durations).toEqual([
      ["customers", "upsert", "ok"],
      ["customers", "count", "ok"],
      ["customers", "delete", "ok"],
      ["refresh_totals", "rpc", "error"],
      ["batch", "batch", "error"],
      ["batch", "batch", "ok"],
    ]);
  });

  it("leaves rpc and batch out when the executor has neither", () => {
    const wrapped = vercelMetrics(() => undefined).wrapExecutor?.({
      name: "postgrest",
      execute: async () => ({ ok: true, data: [] }),
    } as never);

    expect(wrapped && "rpc" in wrapped).toBe(false);
    expect(wrapped && "batch" in wrapped).toBe(false);
  });
});
