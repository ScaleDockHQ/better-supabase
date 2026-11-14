import { describe, expect, it, vi } from "vitest";

import type { BlockContext } from "../../src/blocks/index.ts";
import type { MeterPort } from "../../src/blocks/metering.ts";

import { apiKeysBlock } from "../../src/blocks/api-keys/manifest.ts";
import { createBlocks, defineBlock } from "../../src/blocks/index.ts";
import { meteringHooks, mergeHooks } from "../../src/blocks/metering.ts";
import { organizationsBlock } from "../../src/blocks/organizations/manifest.ts";
import { usageBlock } from "../../src/blocks/usage/manifest.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";

const info = { block: "seats", method: "add" };

const port = (overrides: Partial<MeterPort> = {}): MeterPort => ({
  canConsume: vi.fn(() => AsyncResult.ok(true)),
  current: vi.fn(() =>
    AsyncResult.ok({
      meter: "seats",
      used: 5,
      limit: 5,
      remaining: 0,
      unlimited: false,
      period: "month" as const,
      startsAt: undefined,
      resetsAt: Temporal.Now.instant(),
    }),
  ),
  record: vi.fn(() => AsyncResult.ok({ recorded: true, today: 1, used: 1 })),
  ...overrides,
});

describe("meteringHooks", () => {
  it("refuses with quota_exceeded and the limit when the quota is used up", async () => {
    const canConsume = vi.fn(() => AsyncResult.ok(false));
    const usage = port({ canConsume });

    const { add } = meteringHooks(
      "seats",
      { limits: { add: { meter: "seats" } }, meters: {} },
      usage,
    );

    const refused = await add?.before?.([{ organizationId: "org" }], info);

    expect(refused).toMatchObject({
      kind: "quota_exceeded",
      meter: "seats",
      limit: 5,
    });
    expect(canConsume).toHaveBeenCalledWith({
      organizationId: "org",
      meter: "seats",
      quantity: 1,
    });
  });

  it("lets a call through when it fits or names no tenant", async () => {
    const usage = port();

    const { add } = meteringHooks(
      "seats",
      { limits: { add: { meter: "seats", tenant: "orgId" } }, meters: {} },
      usage,
    );

    expect(await add?.before?.([{ orgId: "org" }], info)).toBeUndefined();
    expect(await add?.before?.([{ orgId: null }], info)).toBeUndefined();
    expect(usage.canConsume).toHaveBeenCalledOnce();
  });

  it("returns the usage error when the check itself fails", async () => {
    const usage = port({
      canConsume: () => AsyncResult.err(dbError("forbidden", "no")),
    });

    const { add } = meteringHooks(
      "seats",
      { limits: { add: { meter: "seats" } }, meters: {} },
      usage,
    );

    expect(
      await add?.before?.([{ organizationId: "org" }], info),
    ).toMatchObject({ kind: "forbidden" });
  });

  it("records the meter after a success and never after a failure", async () => {
    const usage = port();

    const { add } = meteringHooks(
      "seats",
      { limits: {}, meters: { add: { meter: "seats", quantity: 2 } } },
      usage,
    );

    await add?.after?.(
      { ok: false, data: null, error: dbError("conflict", "x") },
      [{ organizationId: "org" }],
      info,
    );
    expect(usage.record).not.toHaveBeenCalled();

    await add?.after?.(
      { ok: true, data: {}, error: null },
      [{ organizationId: "org" }],
      info,
    );
    expect(usage.record).toHaveBeenCalledWith({
      organizationId: "org",
      meter: "seats",
      quantity: 2,
      source: "seats.add",
    });
  });

  it("merges declared hooks before the user's and keeps both afters", async () => {
    const order: string[] = [];

    const merged = mergeHooks(
      {
        before: () => {
          order.push("declared");
        },
        after: () => {
          order.push("declared after");
        },
      },
      {
        before: () => {
          order.push("user");
        },
        after: () => {
          order.push("user after");
        },
      },
    );

    await merged?.before?.([], info);
    await merged?.after?.({ ok: true, data: null, error: null }, [], info);
    expect(order).toEqual(["declared", "user", "declared after", "user after"]);

    const refusal = dbError("quota_exceeded", "full");
    const gate = mergeHooks({ before: () => refusal }, { before: vi.fn() });

    expect(await gate?.before?.([], info)).toBe(refusal);
  });
});

describe("createBlocks metering", () => {
  const transport = {
    call: vi.fn(() => Promise.resolve({ data: null, error: null })),
  };

  /** A tenant block whose `add` declares a limit and a meter. */
  const seatsBlock = defineBlock({
    name: "seats",
    create: (_options: BlockContext) => ({
      add: vi.fn((_input: { organizationId: string }) =>
        AsyncResult.ok("added"),
      ),
    }),
    limits: { add: { meter: "seats" } },
    meters: { add: { meter: "seats" } },
    category: "tenancy",
  });

  const usageStandIn = (usage: MeterPort) =>
    defineBlock({
      name: "usage",
      create: (_options: BlockContext): MeterPort => usage,
      provides: { meter: (client) => client },
      category: "commerce",
    });

  it("applies declarations only with metering on and a usage block", async () => {
    const usage = port({ canConsume: () => AsyncResult.ok(false) });

    const off = createBlocks(
      // SAFETY: a stand-in transport for a block that never calls it.
      { transport },
      { seats: seatsBlock, usage: usageStandIn(usage) },
    );

    expect(await off.seats.add({ organizationId: "org" })).toMatchObject({
      ok: true,
    });

    const alone = createBlocks(
      { transport, metering: true },
      { seats: seatsBlock },
    );

    expect(await alone.seats.add({ organizationId: "org" })).toMatchObject({
      ok: true,
    });

    const on = createBlocks(
      { transport, metering: true },
      { seats: seatsBlock, usage: usageStandIn(usage) },
    );

    expect(await on.seats.add({ organizationId: "org" })).toMatchObject({
      ok: false,
      error: { kind: "quota_exceeded", meter: "seats" },
    });
    expect(usage.record).not.toHaveBeenCalled();
  });

  it("records usage for a call that fits", async () => {
    const usage = port();

    const on = createBlocks(
      { transport, metering: true },
      { seats: seatsBlock, usage: usageStandIn(usage) },
    );

    await on.seats.add({ organizationId: "org" });
    expect(usage.record).toHaveBeenCalledWith(
      expect.objectContaining({ organizationId: "org", meter: "seats" }),
    );
  });

  it("declares the shipped limits on real manifests", () => {
    expect(organizationsBlock.limits).toEqual({ invite: { meter: "seats" } });
    expect(apiKeysBlock.limits["create"]?.meter).toBe("api_keys_created");
    expect(apiKeysBlock.meters["create"]?.meter).toBe("api_keys_created");
    expect(usageBlock.provides.meter).toBeTypeOf("function");
  });
});
