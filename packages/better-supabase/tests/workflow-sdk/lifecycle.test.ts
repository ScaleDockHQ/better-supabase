import { describe, expect, it, vi } from "vitest";

import type { Logger } from "../../src/core/logger.ts";

import { dbError } from "../../src/core/errors.ts";
import { EventHub } from "../../src/core/events.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";

vi.mock(import("workflow/api"), () => ({
  registerLifecycleHooks: vi.fn(() => () => undefined),
  start: vi.fn(),
  getRun: vi.fn(),
  getHookByToken: vi.fn(),
}));

vi.mock(import("workflow/runtime"), () => ({ getWorld: vi.fn() }));

vi.mock(import("workflow"), () => ({ createHook: vi.fn(), sleep: vi.fn() }));

const { registerWorkflowLifecycle, workflowSdkEvents } =
  await import("../../src/workflow-sdk/lifecycle.ts");

type Hooks = Parameters<
  NonNullable<Parameters<typeof registerWorkflowLifecycle>[0]["register"]>
>[0];

function silent(): Logger & { errors: unknown[][] } {
  const errors: unknown[][] = [];

  return {
    debug: () => undefined,
    info: () => undefined,
    warn: () => undefined,
    error: (...args: unknown[]) => {
      errors.push(args);
    },
    errors,
  };
}

function setup(options: {
  emit?: (input: unknown) => unknown;
  events?: EventHub;
  workflows?: (name: string) => boolean;
  logger?: Logger;
}) {
  let hooks: Hooks | undefined;
  const unregister = vi.fn();
  const written: Record<string, unknown>[] = [];

  const stop = registerWorkflowLifecycle({
    ...(options.events ? { events: options.events } : {}),
    outbox: {
      emit: (input) => {
        written.push({ ...input });

        return AsyncResult.from(async () =>
          options.emit ? (options.emit(input) as never) : ok("evt_1"),
        );
      },
    },
    ...(options.workflows ? { workflows: options.workflows } : {}),
    ...(options.logger ? { logger: options.logger } : {}),
    register: (given) => {
      hooks = given;

      return unregister;
    },
  });

  return { hooks: () => hooks!, stop, unregister, written };
}

const run = { runId: "wrun_1" } as never;
const name = "workflow//./src/workflows/order//processOrder";

describe("registerWorkflowLifecycle", () => {
  it("writes a completed run to the outbox keyed on the run and transition", async () => {
    const { hooks, written } = setup({});

    await hooks().onRunCompleted?.({ run, workflowName: name });

    expect(written).toEqual([
      {
        type: "workflow_sdk.run_completed",
        payload: { runId: "wrun_1", workflowName: name },
        subject: "workflow_runs/wrun_1",
        key: "wrun_1:run_completed",
        source: "better-supabase/workflow-sdk",
      },
    ]);
  });

  it("writes a failed run with its code, name and a cut message but no stack", async () => {
    const { hooks, written } = setup({});
    const cause = new RangeError("x".repeat(900));

    await hooks().onRunFailed?.({
      run,
      workflowName: name,
      error: { errorCode: "USER_ERROR", cause } as never,
    });

    const payload = written[0]?.["payload"] as Record<string, string>;

    expect(payload).toMatchObject({
      runId: "wrun_1",
      errorCode: "USER_ERROR",
      errorName: "RangeError",
    });
    expect(payload["errorMessage"]).toHaveLength(500);
    expect(JSON.stringify(written)).not.toContain("stack");
  });

  it("emits block events for traceBlockEvents", async () => {
    const events = new EventHub(silent());
    const seen: string[] = [];
    events.on("block", (event) => seen.push(event.type));
    const { hooks } = setup({ events });

    await hooks().onRunCompleted?.({ run, workflowName: name });

    expect(seen).toEqual(["workflow_sdk.run_completed"]);
    expect(workflowSdkEvents.types).toEqual([
      "workflow_sdk.run_completed",
      "workflow_sdk.run_failed",
    ]);
  });

  it("skips workflows the filter refuses", async () => {
    const { hooks, written } = setup({ workflows: (n) => n.endsWith("//a") });

    await hooks().onRunCompleted?.({ run, workflowName: name });

    expect(written).toEqual([]);
  });

  it("logs a failed or throwing outbox write and never rejects", async () => {
    const logger = silent();

    const failed = setup({
      logger,
      emit: () => err(dbError("network", "down")),
    });

    await expect(
      failed.hooks().onRunCompleted?.({ run, workflowName: name }),
    ).resolves.toBeUndefined();

    const thrown = setup({
      logger,
      emit: () => {
        throw new Error("boom");
      },
    });

    await expect(
      thrown.hooks().onRunCompleted?.({ run, workflowName: name }),
    ).resolves.toBeUndefined();
    expect(logger.errors).toHaveLength(2);
  });

  it("returns the unregister function", () => {
    const { stop, unregister } = setup({});

    expect(stop).toBe(unregister);
  });

  it("needs an outbox or events", () => {
    expect(() => registerWorkflowLifecycle({})).toThrow(TypeError);
  });
});
