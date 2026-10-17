import { Temporal } from "temporal-polyfill";
import { describe, expect, it, vi } from "vitest";

import type { UsageStatus } from "../../../src/blocks/usage/usage.ts";

import { createUsageMeterController } from "../../../src/blocks/usage/client.ts";
import {
  failed,
  fakeAuth,
  flush,
  held,
  mount,
  resolved,
} from "../../fixtures/ports.ts";

const status = (
  meter: string,
  used: number,
  limit: number | undefined,
  unlimited = false,
): UsageStatus => ({
  meter,
  used,
  limit,
  remaining: limit === undefined ? undefined : Math.max(0, limit - used),
  unlimited,
  period: "month",
  startsAt: undefined,
  resetsAt: Temporal.Instant.from("2026-11-01T00:00:00Z"),
});

const overview = [
  status("api.calls", 250, 1000),
  status("customers.created", 30, 25),
  status("seats", 4, undefined, true),
  status("exports", 0, 0),
];

describe("createUsageMeterController", () => {
  it("reads every meter with its fraction of the quota", async () => {
    const client = { overview: vi.fn(() => resolved(overview)) };

    const { view, unmount } = mount(
      createUsageMeterController({
        client,
        auth: fakeAuth(),
        organizationId: "org-1",
      }),
    );

    await flush();
    expect(client.overview).toHaveBeenCalledWith("org-1");
    expect(
      view().meters?.map((meter) => [
        meter.meter,
        meter.fraction,
        meter.exceeded,
      ]),
    ).toEqual([
      ["api.calls", 0.25, false],
      ["customers.created", 1, true],
      ["seats", undefined, false],
      ["exports", 1, true],
    ]);
    client.overview.mockReturnValue(failed("denied"));
    await view().refresh();
    expect(view().error?.message).toBe("denied");
    unmount();
  });

  it("keeps the meters it is asked for, in that order", async () => {
    const client = { overview: vi.fn(() => resolved(overview)) };

    const { view, unmount } = mount(
      createUsageMeterController({
        client,
        auth: fakeAuth(),
        organizationId: "org-1",
        meters: ["customers.created", "missing", "api.calls"],
      }),
    );

    await flush();
    expect(view().meters?.map((meter) => meter.meter)).toEqual([
      "customers.created",
      "api.calls",
    ]);
    unmount();
  });

  it("waits for an organization and drops stale answers", async () => {
    const waiting = { overview: vi.fn(() => resolved(overview)) };

    const idle = createUsageMeterController({
      client: waiting,
      auth: fakeAuth(),
      organizationId: null,
    });

    const mounted = mount(idle);
    await mounted.view().refresh();
    mounted.unmount();
    expect(waiting.overview).not.toHaveBeenCalled();

    const answer = held(overview);
    const slow = { overview: vi.fn(() => answer.result) };

    const controller = createUsageMeterController({
      client: slow,
      auth: fakeAuth(),
      organizationId: "org-1",
    });

    const view = mount(controller);
    await flush();
    view.unmount();
    answer.release();
    await flush();
    expect(controller.getSnapshot().meters).toBeUndefined();
  });
});
