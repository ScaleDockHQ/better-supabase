import { describe, expect, it } from "vitest";

import type { Executor } from "../../src/core/executor.ts";

import { createSupabase } from "../../src/core/define.ts";
import { ok } from "../../src/core/result.ts";
import { EMPTY_STATS, StatsRecorder } from "../../src/core/stats.ts";
import { schema } from "../fixtures/generated-camel.ts";

const tick = (): Promise<void> =>
  new Promise((done) => {
    setTimeout(done, 1);
  });

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
    const db = createSupabase(schema).connect(executor);
    expect(db.$stats()).toEqual(EMPTY_STATS);

    await Promise.all([db.customers.list(), db.notes.list()]);
    await db.customers.count();
    await db.$with({ claims: { tenant_id: "o" } }).tags.list();
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
    const betterSupabase = createSupabase(schema);
    const request = new StatsRecorder();
    const one = betterSupabase.connect(executor, {}, { stats: request });
    const two = betterSupabase.connect(executor, {}, { stats: request });
    await Promise.all([one.customers.list(), two.customers.list()]);
    await two.notes.list();
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

describe("StatsRecorder verifications and admin calls", () => {
  it("counts them and reports into the parent", () => {
    const parent = new StatsRecorder();
    const child = new StatsRecorder(parent);

    child.verification();
    child.begin("customers", true)();
    child.begin("notes")();

    expect(child.snapshot()).toMatchObject({
      calls: 2,
      verifications: 1,
      adminCalls: 1,
    });
    expect(parent.snapshot()).toMatchObject({
      calls: 2,
      verifications: 1,
      adminCalls: 1,
    });
  });
});
