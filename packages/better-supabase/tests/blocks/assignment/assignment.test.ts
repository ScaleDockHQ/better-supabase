import { describe, expect, it, vi } from "vitest";

import {
  assignmentBlock,
  assignmentQueueInputSchema,
  createAssignment,
} from "../../../src/blocks/assignment/index.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";

const territory = {
  id: "root",
  type: "group",
  combinator: "and",
  rules: [
    { id: "r1", type: "rule", path: ["country"], operator: "eq", value: "NL" },
  ],
};

const queueRow = {
  id: "q1",
  organizationId: "org",
  name: "Benelux",
  subjectType: "company",
  strategy: "weighted",
  conditions: territory,
  rank: 0,
  enabled: true,
  members: [
    {
      userId: "u1",
      weight: 3,
      active: true,
      assignedCount: 2,
      lastAssignedAt: AT,
    },
    {
      userId: "u2",
      weight: 1,
      active: false,
      assignedCount: 0,
      lastAssignedAt: null,
    },
  ],
  createdAt: AT,
  updatedAt: AT,
};

const answers = {
  save_assignment_queue: queueRow,
  set_assignment_members: { ...queueRow, conditions: null, enabled: false },
  remove_assignment_queue: true,
  list_assignment_queues: [{ ...queueRow, strategy: "round_robin" }],
  assign_subject: { queueId: "q1", userId: "u1", strategy: "weighted" },
  assignment_history: [
    { queueId: "q1", userId: "u1", assignedAt: AT },
    { queueId: null, userId: null, assignedAt: AT },
  ],
};

describe("createAssignment", () => {
  it("manages queues and picks owners", async () => {
    const { transport, call } = fakeTransport(answers);
    const assignment = createAssignment({ transport });

    const queue = await assignment
      .saveQueue("org", {
        name: "Benelux",
        subjectType: "company",
        strategy: "weighted",
        conditions: territory,
      })
      .orThrow();

    expect(queue).toMatchObject({
      id: "q1",
      strategy: "weighted",
      conditions: territory,
      enabled: true,
    });
    expect(queue.members).toEqual([
      {
        userId: "u1",
        weight: 3,
        active: true,
        assignedCount: 2,
        lastAssignedAt: Temporal.Instant.from(AT),
      },
      {
        userId: "u2",
        weight: 1,
        active: false,
        assignedCount: 0,
        lastAssignedAt: undefined,
      },
    ]);

    const cleared = await assignment
      .setMembers("q1", [{ userId: "u1", weight: 3 }])
      .orThrow();

    expect(cleared.conditions).toBeUndefined();
    expect(cleared.enabled).toBe(false);
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "set_assignment_members",
      { queue: "q1", members: [{ userId: "u1", weight: 3 }] },
    );

    expect(await assignment.removeQueue("q1").orThrow()).toBe(true);

    const [listed] = await assignment.queues("org").orThrow();

    expect(listed?.strategy).toBe("round_robin");
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "list_assignment_queues",
      { tenant: "org", subject_type: null },
    );
    await assignment.queues("org", { subjectType: "company" }).orThrow();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "list_assignment_queues",
      { tenant: "org", subject_type: "company" },
    );

    expect(
      await assignment
        .assign("org", { type: "company", id: "c1", fields: { country: "NL" } })
        .orThrow(),
    ).toEqual({ queueId: "q1", userId: "u1", strategy: "weighted" });
    await assignment.assign("org", { type: "company", id: "c2" }).orThrow();
    expect(call).toHaveBeenLastCalledWith("better_supabase", "assign_subject", {
      tenant: "org",
      subject_type: "company",
      subject_id: "c2",
      subject: {},
    });

    expect(
      await assignment.history("org", { type: "company", id: "c1" }).orThrow(),
    ).toEqual([
      { queueId: "q1", userId: "u1", assignedAt: Temporal.Instant.from(AT) },
      {
        queueId: undefined,
        userId: undefined,
        assignedAt: Temporal.Instant.from(AT),
      },
    ]);
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "assignment_history",
      {
        tenant: "org",
        subject_type: "company",
        subject_id: "c1",
        max_count: null,
      },
    );
    await assignment
      .history("org", { type: "company", id: "c1" }, { limit: 5 })
      .orThrow();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "assignment_history",
      {
        tenant: "org",
        subject_type: "company",
        subject_id: "c1",
        max_count: 5,
      },
    );
  });

  it("returns undefined when no queue matches", async () => {
    const { transport } = fakeTransport({ assign_subject: null });

    expect(
      await createAssignment({ transport, schema: "api" })
        .assign("org", { type: "company", id: "c1" })
        .orThrow(),
    ).toBeUndefined();

    const { transport: empty } = fakeTransport({ assign_subject: undefined });

    expect(
      await createAssignment({ transport: empty })
        .assign("org", { type: "company", id: "c1" })
        .orThrow(),
    ).toBeUndefined();
  });

  it("rejects an unknown strategy and logs failures", async () => {
    const { transport } = fakeTransport({
      save_assignment_queue: { ...queueRow, strategy: "random" },
    });

    const logger = {
      debug: vi.fn(),
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    };

    const result = await createAssignment({ transport, logger }).saveQueue(
      "org",
      { name: "x" },
    );

    expect(result.ok).toBe(false);
  });

  it("validates input and declares the manifest", async () => {
    const validate = assignmentQueueInputSchema["~standard"].validate;

    expect(
      (await validate({ name: "Benelux", strategy: "round_robin" })).issues,
    ).toBeUndefined();
    expect((await validate({ strategy: "random" })).issues).toBeDefined();
    expect(assignmentBlock.name).toBe("assignment");
  });
});
