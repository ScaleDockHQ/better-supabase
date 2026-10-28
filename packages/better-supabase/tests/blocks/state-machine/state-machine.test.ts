import { describe, expect, it } from "vitest";

import { createStateMachine } from "../../../src/blocks/state-machine/index.ts";

function recording(results: Record<string, unknown>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  return {
    calls,
    transport: {
      call(_schema: string, fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });

        return Promise.resolve(results[fn]);
      },
    },
  };
}

describe("state machine block", () => {
  it("pauses, resumes and flags a record as the caller", async () => {
    const { calls, transport } = recording({
      pause_lifecycle: true,
      resume_lifecycle: false,
      set_lifecycle_flag: true,
    });

    const machine = createStateMachine<"quote">({ transport });
    const until = Temporal.Instant.from("2026-11-01T00:00:00Z");
    expect(
      await machine
        .pause({ type: "quote", id: "q1" }, { until, reason: "waiting" })
        .orThrow(),
    ).toBe(true);
    expect(await machine.pause({ type: "quote", id: "q2" }).orThrow()).toBe(
      true,
    );
    expect(await machine.resume({ type: "quote", id: "q1" }).orThrow()).toBe(
      false,
    );
    expect(
      await machine
        .setFlag({ type: "quote", id: "q1" }, "urgent", true)
        .orThrow(),
    ).toBe(true);
    expect(calls).toEqual([
      {
        fn: "pause_lifecycle",
        args: {
          subject_type: "quote",
          subject_id: "q1",
          until: "2026-11-01T00:00:00Z",
          reason: "waiting",
        },
      },
      {
        fn: "pause_lifecycle",
        args: {
          subject_type: "quote",
          subject_id: "q2",
          until: null,
          reason: null,
        },
      },
      {
        fn: "resume_lifecycle",
        args: { subject_type: "quote", subject_id: "q1" },
      },
      {
        fn: "set_lifecycle_flag",
        args: {
          subject_type: "quote",
          subject_id: "q1",
          flag: "urgent",
          enabled: true,
        },
      },
    ]);
  });

  it("reads a record's state", async () => {
    const { transport } = recording({
      status_state: {
        organizationId: "org",
        subjectType: "quote",
        subjectId: "q1",
        status: "sent",
        order: ["draft", "sent", "accepted"],
        step: 2,
        steps: 3,
        progress: 0.5,
        version: 2,
        workflow: "deal-stages",
        workflowVersionId: "wv1",
        flags: ["urgent"],
        paused: true,
        pausedAt: "2026-10-01T00:00:00Z",
        pausedUntil: null,
        pauseReason: "waiting",
      },
    });

    const state = await createStateMachine({ transport })
      .state({ type: "quote", id: "q1" })
      .orThrow();

    expect(state).toMatchObject({
      organizationId: "org",
      subject: { type: "quote", id: "q1" },
      status: "sent",
      order: ["draft", "sent", "accepted"],
      step: 2,
      steps: 3,
      progress: 0.5,
      version: 2,
      workflow: "deal-stages",
      workflowVersionId: "wv1",
      flags: ["urgent"],
      paused: true,
      pausedUntil: undefined,
      pauseReason: "waiting",
    });
    expect(state.pausedAt?.toString()).toBe("2026-10-01T00:00:00Z");
  });

  it("leaves step and progress undefined outside the order", async () => {
    const { transport } = recording({
      status_state: {
        organizationId: "org",
        subjectType: "quote",
        subjectId: "q1",
        status: "void",
        order: [],
        step: null,
        steps: null,
        progress: null,
        version: null,
        flags: [],
        paused: false,
      },
    });

    const state = await createStateMachine({ transport })
      .state({ type: "quote", id: "q1" })
      .orThrow();

    expect(state.step).toBeUndefined();
    expect(state.progress).toBeUndefined();
    expect(state.version).toBeUndefined();
    expect(state.workflowVersionId).toBeUndefined();
    expect(state.paused).toBe(false);
  });

  it("pages history with the last createdAt as the cursor", async () => {
    const { calls, transport } = recording({
      list_status_history: [
        {
          id: "h2",
          from: "draft",
          to: "sent",
          actorId: "u1",
          reason: null,
          createdAt: "2026-10-02T00:00:00Z",
        },
      ],
    });

    const machine = createStateMachine({ transport });

    const history = await machine
      .history(
        { type: "quote", id: "q1" },
        { cursor: Temporal.Instant.from("2026-10-03T00:00:00Z"), limit: 10 },
      )
      .orThrow();

    expect(history).toHaveLength(1);
    expect(history[0]).toMatchObject({
      id: "h2",
      from: "draft",
      to: "sent",
      actorId: "u1",
      reason: undefined,
    });
    expect(history[0]?.createdAt.toString()).toBe("2026-10-02T00:00:00Z");
    expect(calls[0]?.args).toEqual({
      subject_type: "quote",
      subject_id: "q1",
      before: "2026-10-03T00:00:00Z",
      max_rows: 10,
    });
  });

  it("passes the reason and actor of a transition and reads them back", async () => {
    const { calls, transport } = recording({
      transition: true,
      list_status_history: [
        {
          id: "h3",
          from: "sent",
          to: "accepted",
          actorId: null,
          actorName: "Ada Client",
          actorEmail: "ada@example.com",
          ip: "203.0.113.7",
          userAgent: "Mozilla/5.0",
          reason: "signed",
          createdAt: "2026-10-04T00:00:00Z",
        },
      ],
    });

    const machine = createStateMachine<"quote">({ transport });

    const actor = {
      name: "Ada Client",
      email: "ada@example.com",
      ip: "203.0.113.7",
      userAgent: "Mozilla/5.0",
    };

    expect(
      await machine
        .transition({ type: "quote", id: "q1" }, "accepted", {
          reason: "signed",
          actor,
        })
        .orThrow(),
    ).toBe(true);
    expect(
      await machine.transition({ type: "quote", id: "q2" }, "sent").orThrow(),
    ).toBe(true);
    expect(calls.map((call) => call.args)).toEqual([
      {
        subject_type: "quote",
        subject_id: "q1",
        to_status: "accepted",
        reason: "signed",
        actor,
      },
      {
        subject_type: "quote",
        subject_id: "q2",
        to_status: "sent",
        reason: null,
        actor: null,
      },
    ]);

    const [change] = await machine
      .history({ type: "quote", id: "q1" })
      .orThrow();

    expect(change).toMatchObject({
      actorId: undefined,
      actorName: "Ada Client",
      actorEmail: "ada@example.com",
      ip: "203.0.113.7",
      userAgent: "Mozilla/5.0",
      reason: "signed",
    });
  });

  it("reads the stages timeline", async () => {
    const { transport } = recording({
      list_status_stages: [
        {
          id: "s1",
          label: "draft",
          outcome: null,
          display: 1,
          clearedAt: "2026-10-02T00:00:00Z",
          createdAt: "2026-10-01T00:00:00Z",
        },
        {
          id: "s2",
          label: "sent",
          outcome: null,
          display: 2,
          clearedAt: null,
          createdAt: "2026-10-02T00:00:00Z",
        },
      ],
    });

    const stages = await createStateMachine({ transport })
      .stages({ type: "quote", id: "q1" })
      .orThrow();

    expect(stages.map((stage) => stage.label)).toEqual(["draft", "sent"]);
    expect(stages[1]?.clearedAt).toBeUndefined();
    expect(stages[0]?.display).toBe(1);
  });

  it("fails on a malformed reply", async () => {
    const { transport } = recording({ status_state: "nope" });

    const result = await createStateMachine({ transport }).state({
      type: "quote",
      id: "q1",
    });

    expect(result.ok).toBe(false);
  });
});
