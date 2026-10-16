import { describe, expect, it } from "vitest";

import { createSla } from "../../../src/blocks/sla/index.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];
  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const result = results[fn];
      if (!result) return Promise.reject(new Error(`unexpected ${fn}`));
      return Promise.resolve(result(args));
    },
  };
}

const CLOCK = {
  id: "c1",
  subject_type: "ticket",
  subject_id: "t1",
  metric: "resolution",
  state: "paused",
  started_at: "2026-10-15T09:00:00Z",
  due_at: "2026-10-16T09:00:00Z",
  secondsLeft: 3600,
  paused_at: "2026-10-15T12:00:00Z",
  warned_at: null,
  breached_at: null,
  met_at: null,
};

describe("sla block", () => {
  it("saves a policy with the attributes it names", async () => {
    const t = transport({
      save_sla_policy: () => ({
        id: "p1",
        subject_type: "ticket",
        name: "Urgent",
        priority: "urgent",
        first_response_minutes: 30,
        next_response_minutes: null,
        resolution_minutes: 240,
        warn_at_percent: 50,
        business_hours: true,
      }),
    });
    const policy = await createSla({ transport: t })
      .savePolicy("o", {
        subjectType: "ticket",
        name: "Urgent",
        priority: "urgent",
        firstResponseMinutes: 30,
      })
      .orThrow();
    expect(policy).toEqual({
      id: "p1",
      subjectType: "ticket",
      name: "Urgent",
      priority: "urgent",
      firstResponseMinutes: 30,
      resolutionMinutes: 240,
      warnAtPercent: 50,
      businessHours: true,
      fields: {},
    });
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      policy: null,
      attrs: {
        subjectType: "ticket",
        name: "Urgent",
        priority: "urgent",
        firstResponseMinutes: 30,
      },
    });
  });

  it("starts, records, reads, checks and computes due times", async () => {
    const t = transport({
      start_sla_clocks: () => [CLOCK],
      record_sla_event: () => [
        {
          ...CLOCK,
          state: "met",
          met_at: "2026-10-15T13:00:00Z",
          secondsLeft: null,
        },
      ],
      sla_clocks_of: () => [CLOCK],
      check_sla_clocks: () => 2,
      sla_due_at: () => "2026-10-19T08:00:00Z",
    });
    const sla = createSla({ transport: t });
    const ticket = { type: "ticket", id: "t1" };
    expect((await sla.start(ticket, "urgent").orThrow())[0]).toMatchObject({
      state: "paused",
      secondsLeft: 3600,
    });
    const met = await sla.record(ticket, "resolved").orThrow();
    expect(met[0]?.metAt).toBeDefined();
    expect(met[0]?.secondsLeft).toBeUndefined();
    await sla.clocks(ticket).orThrow();
    expect(await sla.check().orThrow()).toBe(2);
    const due = await sla
      .dueAt(Temporal.Instant.from("2026-10-16T14:00:00Z"), 120, true)
      .orThrow();
    expect(due.toString()).toBe("2026-10-19T08:00:00Z");
    expect(t.calls.map(([, args]) => args)).toEqual([
      { subject_type: "ticket", subject_id: "t1", priority: "urgent" },
      { subject_type: "ticket", subject_id: "t1", event: "resolved" },
      { subject_type: "ticket", subject_id: "t1" },
      {},
      { start: "2026-10-16T14:00:00Z", minutes: 120, business: true },
    ]);
    await sla.start(ticket).orThrow();
    expect(t.calls[5]?.[1]).toMatchObject({ priority: null });
  });
});
