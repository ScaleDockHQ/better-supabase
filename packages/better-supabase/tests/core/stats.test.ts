import { describe, expect, it } from "vitest";

import type { Executor } from "../../src/core/executor.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { ok } from "../../src/core/result.ts";
import { StatsRecorder } from "../../src/core/stats.ts";
import { schema } from "../fixtures/generated-camel.ts";

const tick = (): Promise<void> => new Promise((done) => setTimeout(done, 1));

const executor: Executor = {
  name: "fake",
  execute: async () => {
    await tick();
    return ok({ rows: [], count: 0 });
  },
  rpc: async () => {
    await tick();
    return ok(null);
  },
};

describe("db.$stats()", () => {
  it("counts calls, waves and tables", async () => {
    const db = defineSupabase(schema).connect(executor);
    expect(db.$stats()).toEqual({ calls: 0, waves: 0, tables: [], ms: 0 });

    await Promise.all([db.customers.findMany(), db.notes.findMany()]);
    await db.customers.count();
    await db.$with({ claims: { tenant_id: "o" } }).tags.findMany();
    await db.$rpc("customer_stats" as never, {} as never);

    const stats = db.$stats();
    expect(stats).toMatchObject({
      calls: 5,
      waves: 4,
      tables: ["customers", "notes", "tags", "customer_stats()"],
    });
    expect(stats.ms).toBeGreaterThan(0);
  });

  it("reports into a request-wide recorder", async () => {
    const sb = defineSupabase(schema);
    const request = new StatsRecorder();
    const one = sb.connect(executor, {}, { stats: request });
    const two = sb.connect(executor, {}, { stats: request });
    await Promise.all([one.customers.findMany(), two.customers.findMany()]);
    await two.notes.findMany();
    expect(one.$stats()).toMatchObject({ calls: 1, waves: 1 });
    expect(request.snapshot()).toMatchObject({
      calls: 3,
      waves: 2,
      tables: ["customers", "notes"],
    });
  });

  it("ends a call once even when its end runs twice", () => {
    const recorder = new StatsRecorder();
    const end = recorder.begin("customers");
    end();
    end();
    recorder.begin("customers")();
    expect(recorder.snapshot()).toMatchObject({ calls: 2, waves: 2 });
  });
});
