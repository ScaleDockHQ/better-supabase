import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type { ScheduleProvider } from "../../../src/blocks/queue/backends.ts";

import {
  createQueue,
  vercelQueueProvider,
} from "../../../src/blocks/queue/index.ts";
import { fakeVercelQueues } from "./vercel-fakes.ts";

const queues = { reports: v.object({ kind: v.string() }) };

const AT = Temporal.Instant.from("2026-12-01T09:00:00Z");

function bare(): ScheduleProvider {
  return {
    apiVersion: 1,
    name: "bare",
    schedule: async () => undefined,
    unschedule: async () => false,
  };
}

function full() {
  const calls: unknown[][] = [];

  const scheduler: ScheduleProvider = {
    ...bare(),
    name: "full",
    scheduleOnce: async (...args) => {
      calls.push(["once", ...args]);
    },
    getSchedule: async (name, tenant) => {
      calls.push(["get", name, tenant]);

      return null;
    },
    enableSchedule: async (...args) => {
      calls.push(["enable", ...args]);

      return true;
    },
    disableSchedule: async (...args) => {
      calls.push(["disable", ...args]);

      return true;
    },
    runScheduleNow: async (...args) => {
      calls.push(["run", ...args]);

      return false;
    },
  };

  return { calls, scheduler };
}

const jobsWith = (scheduler: ScheduleProvider) =>
  createQueue({
    backend: vercelQueueProvider(fakeVercelQueues().client),
    scheduler,
    queues,
  });

describe("queue schedule methods", () => {
  it("passes one-time and lifecycle calls to the scheduler", async () => {
    const { calls, scheduler } = full();
    const jobs = jobsWith(scheduler);

    await jobs
      .scheduleOnce({
        name: "remind",
        at: AT,
        queue: "reports",
        payload: { kind: "daily" },
      })
      .orThrow();
    await jobs
      .scheduleOnce({
        name: "remind",
        at: AT,
        queue: "reports",
        payload: { kind: "daily" },
        timeZone: "Europe/Amsterdam",
        tenant: "acme",
        probe: "p1",
      })
      .orThrow();

    expect(await jobs.getSchedule("remind").orThrow()).toBeNull();
    expect(
      await jobs
        .enableSchedule("remind", { tenant: "acme", until: AT })
        .orThrow(),
    ).toBe(true);
    expect(await jobs.enableSchedule("remind").orThrow()).toBe(true);
    expect(
      await jobs.disableSchedule("remind", { tenant: "acme" }).orThrow(),
    ).toBe(true);
    expect(await jobs.disableSchedule("remind").orThrow()).toBe(true);
    expect(await jobs.runSchedule("remind", { tenant: "acme" }).orThrow()).toBe(
      false,
    );
    expect(await jobs.runSchedule("remind").orThrow()).toBe(false);

    expect(calls).toEqual([
      [
        "once",
        "remind",
        AT,
        "reports",
        { kind: "daily" },
        "UTC",
        undefined,
        undefined,
      ],
      [
        "once",
        "remind",
        AT,
        "reports",
        { kind: "daily" },
        "Europe/Amsterdam",
        "acme",
        "p1",
      ],
      ["get", "remind", undefined],
      ["enable", "remind", "acme", AT],
      ["enable", "remind", undefined, undefined],
      ["disable", "remind", "acme"],
      ["disable", "remind", undefined],
      ["run", "remind", "acme"],
      ["run", "remind", undefined],
    ]);
  });

  it("takes the tenant of a one-time schedule from the request context", async () => {
    const { calls, scheduler } = full();

    await jobsWith(scheduler)
      .scheduleOnce({
        name: "remind",
        at: AT,
        queue: "reports",
        payload: { kind: "daily" },
        context: { tenant: "acme" },
      })
      .orThrow();

    expect(calls[0]?.[6]).toBe("acme");
  });

  it("refuses a payload the queue's schema rejects before scheduling", async () => {
    const { calls, scheduler } = full();

    const result = await jobsWith(scheduler).scheduleOnce({
      name: "remind",
      at: AT,
      queue: "reports",
      // SAFETY: a payload the schema refuses.
      payload: { kind: 1 } as never,
    });

    expect(result.ok).toBe(false);
    expect(calls).toEqual([]);
  });

  it("answers invalid_request when the scheduler lacks the feature", async () => {
    const jobs = jobsWith(bare());

    const results = [
      await jobs.scheduleOnce({
        name: "x",
        at: AT,
        queue: "reports",
        payload: { kind: "daily" },
      }),
      await jobs.getSchedule("x"),
      await jobs.enableSchedule("x"),
      await jobs.disableSchedule("x"),
      await jobs.runSchedule("x"),
    ];

    for (const result of results) {
      expect(!result.ok && result.error).toMatchObject({
        kind: "invalid_request",
        message: expect.stringContaining('the "bare" scheduler'),
      });
    }
  });
});
