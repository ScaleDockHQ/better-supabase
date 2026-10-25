import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { BlockContext } from "../../src/blocks/index.ts";

import { defineBlock, defineBlocks } from "../../src/blocks/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { instanceProperty } from "../../src/core/instance-property.ts";
import { ok } from "../../src/core/result.ts";
import { schema } from "../fixtures/generated-camel.ts";

/** A block whose client reports the tenant it acts in. */
const probe = defineBlock({
  name: "probe",
  create: (context: BlockContext) => ({
    tenant: (): string | undefined =>
      typeof context.tenant === "function"
        ? (context.tenant() ?? undefined)
        : context.tenant,
  }),
  category: "work",
});

const config = {
  probe: { schema: "better_supabase", api: "api", options: {} },
  "lead-scoring": { block: "probe", schema: "better_supabase", options: {} },
} as const;

const blockSet = defineBlocks(config, { probe, "lead-scoring": probe });

const rpc = vi.fn(async () => ok({ rows: [{ value: 1 }], count: null }));

const executor = {
  name: "fake",
  execute: async () => ok({ rows: [], count: 0 }),
  rpc,
};

const betterSupabase = defineSupabase(schema).blocks(blockSet);

describe("block instances on db", () => {
  it("puts each instance under its key in camel case", () => {
    const db = betterSupabase.connect(executor, { tenant: "org-1" });

    expect(db.probe.tenant()).toBe("org-1");
    expect(db.leadScoring.tenant()).toBe("org-1");
    expect(instanceProperty("lead-scoring")).toBe("leadScoring");
    expect(instanceProperty("billable_time")).toBe("billableTime");
  });

  it("builds a client once per db and acts in that db's organization", () => {
    const db = betterSupabase.connect(executor, { tenant: "org-1" });
    const other = db.$with({ tenant: "org-2" });

    expect(db.probe).toBe(db.probe);
    expect(other.probe).not.toBe(db.probe);
    expect(other.probe.tenant()).toBe("org-2");
  });

  it("keeps the tables next to the instances", () => {
    const db = betterSupabase.connect(executor, {});

    expect(db.customers).toBeDefined();
    expect(Object.keys(db)).not.toContain("probe");
  });

  it("calls the API schema through $api", async () => {
    const db = betterSupabase.connect(executor, {});

    await db.$api("ping", { a: 1, b: undefined });

    expect(rpc).toHaveBeenCalledWith(
      "ping",
      { a: 1 },
      expect.objectContaining({ schema: "api" }),
    );
  });

  it("returns the API schema call as a Result through $apiResult", async () => {
    const db = betterSupabase.connect(executor, {});
    const result = await db.$apiResult("ping", { a: 1 });

    expect(result).toMatchObject({ ok: true });

    const failing = betterSupabase.connect(
      {
        ...executor,
        rpc: vi.fn(() =>
          Promise.reject(
            Object.assign(new Error("denied"), {
              code: "42501",
              hint: "PING_FORBIDDEN",
            }),
          ),
        ),
      },
      {},
    );

    const denied = await failing.$apiResult("ping", {});

    expect(denied.ok).toBe(false);
    expect(denied.ok ? undefined : denied.error.kind).toBe("forbidden");
    expect(denied.ok ? undefined : denied.error.hint).toBe("PING_FORBIDDEN");
    await expect(failing.$api("ping", {})).rejects.toThrow("denied");
  });

  it("passes the definition's temporal to every instance", () => {
    const seen: unknown[] = [];
    const temporal = globalThis.Temporal;

    const recorder = defineBlock({
      name: "recorder",
      create: (context: BlockContext) => {
        seen.push(context.temporal);

        return { ping: (): boolean => true };
      },
      category: "work",
    });

    const db = defineSupabase(schema, { temporal })
      .blocks(
        defineBlocks(
          {
            recorder: { schema: "better_supabase", options: {} },
            second: {
              block: "recorder",
              schema: "better_supabase",
              options: {},
            },
          },
          { recorder, second: recorder },
        ),
      )
      .connect(executor, {});

    expect(db.recorder.ping()).toBe(true);
    expect(db.second.ping()).toBe(true);
    expect(seen).toEqual([temporal, temporal]);
  });

  it("leaves a table its property and keeps the instance under $blocks", () => {
    const clash = defineSupabase(schema).blocks(
      defineBlocks(
        {
          customers: { block: "probe", schema: "better_supabase", options: {} },
        },
        { customers: probe },
      ),
    );

    const db = clash.connect(executor, {});

    expect(typeof db.customers.list).toBe("function");
    expect(db.$blocks.customers.tenant()).toBeUndefined();
    expect(Object.keys(db.$blocks)).toEqual(["customers"]);
  });

  it("types the instances by property", () => {
    const db = betterSupabase.connect(executor, {});

    expectTypeOf(db.leadScoring.tenant).returns.toEqualTypeOf<
      string | undefined
    >();
    // @ts-expect-error not an instance
    void db.leadscoring;
    // @ts-expect-error a definition without blocks has no $api
    void defineSupabase(schema).connect(executor, {}).$api;
  });
});
