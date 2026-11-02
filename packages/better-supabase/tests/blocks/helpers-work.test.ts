import { describe, expect, it } from "vitest";

import { createApprovals } from "../../src/blocks/approvals/index.ts";
import { createAutomationsAdmin } from "../../src/blocks/automations/index.ts";
import { createCases } from "../../src/blocks/cases/index.ts";
import { createEnrollments } from "../../src/blocks/enrollments/index.ts";
import { createInbox } from "../../src/blocks/inbox/index.ts";
import { createIncidents } from "../../src/blocks/incidents/index.ts";
import { createMeetings } from "../../src/blocks/meetings/index.ts";
import { createRank } from "../../src/blocks/rank/index.ts";
import { createTasks } from "../../src/blocks/tasks/index.ts";
import { fieldsTransport } from "./fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";

const TASK = {
  id: "w1",
  tenant_id: "o",
  number: 1,
  identifier: "TASK-1",
  title: "Ship",
  state: "completed",
  locked: false,
  rank: "V",
  created_at: AT,
  updated_at: AT,
};

const MOVED = {
  accepted: [{ workItemId: "w1", field: "stageId" }],
  rejected: [],
};

describe("tasks.complete, cancel and reopen", () => {
  it("move the item and check the state its stage gives", async () => {
    const t = fieldsTransport({
      update_tasks: () => MOVED,
      get_task: () => TASK,
    });

    const tasks = createTasks({ transport: t });

    expect(
      await tasks.complete({ workItemId: "w1", stageId: "done" }).orThrow(),
    ).toBe(true);
    expect(t.calls.map(([fn]) => fn)).toEqual(["update_tasks", "get_task"]);
  });

  it("fail when the stage is of another category", async () => {
    const t = fieldsTransport({
      update_tasks: () => MOVED,
      get_task: () => ({ ...TASK, state: "started" }),
    });

    const tasks = createTasks({ transport: t });

    const canceled = await tasks.cancel({ workItemId: "w1", stageId: "doing" });
    expect(canceled.ok ? undefined : canceled.error.kind).toBe("invalid_input");

    expect(
      await tasks.reopen({ workItemId: "w1", stageId: "doing" }).orThrow(),
    ).toBe(true);
  });
});

describe("tasks.assignToMe", () => {
  it("adds the user and keeps the other assignees", async () => {
    const t = fieldsTransport({
      get_task: () => ({ ...TASK, assignees: ["u1"] }),
      set_task_assignees: () => 2,
    });

    const tasks = createTasks({ transport: t });

    expect(
      await tasks.assignToMe({ workItemId: "w1", userId: "u2" }).orThrow(),
    ).toBe(2);
    expect(t.calls[1]).toEqual([
      "set_task_assignees",
      { work_item: "w1", users: ["u1", "u2"] },
    ]);
  });

  it("does nothing when the user is assigned", async () => {
    const t = fieldsTransport({
      get_task: () => ({ ...TASK, assignees: ["u1"] }),
    });

    const tasks = createTasks({ transport: t });

    expect(
      await tasks.assignToMe({ workItemId: "w1", userId: "u1" }).orThrow(),
    ).toBe(1);
    expect(t.calls).toHaveLength(1);
  });
});

describe("cases.tryClose", () => {
  it("returns the blockers without closing", async () => {
    const t = fieldsTransport({
      case_close_blockers: () => ["CASE_ACTIONS_OPEN"],
    });

    const result = await createCases({ transport: t, tenant: "org-1" })
      .tryClose({ caseId: "c1" })
      .orThrow();

    expect(result).toEqual({ closed: false, blockers: ["CASE_ACTIONS_OPEN"] });
    expect(t.calls.map(([fn]) => fn)).toEqual(["case_close_blockers"]);
  });

  it("closes the case when nothing blocks it", async () => {
    const t = fieldsTransport({
      case_close_blockers: () => [],
      close_case: () => ({
        id: "c1",
        organizationId: "org-1",
        kindId: "k1",
        number: "CMP-1",
        title: "Late",
        source: "customer",
        status: "closed",
        createdAt: AT,
        updatedAt: AT,
        fields: {},
      }),
    });

    const result = await createCases({ transport: t, tenant: "org-1" })
      .tryClose({ caseId: "c1", note: "done" })
      .orThrow();

    expect(result.closed).toBe(true);
    expect(t.calls[1]?.[0]).toBe("close_case");
  });
});

describe("incidents.resolve", () => {
  it("posts a resolved update", async () => {
    const t = fieldsTransport({
      post_incident_update: () => ({
        id: "u1",
        incidentId: "i1",
        status: "resolved",
        body: "Fixed",
        public: true,
        createdAt: AT,
      }),
    });

    await createIncidents({ transport: t })
      .resolve({ incidentId: "i1", body: "Fixed" })
      .orThrow();

    expect(t.calls[0]).toEqual([
      "post_incident_update",
      { incident_id: "i1", status: "resolved", body: "Fixed", is_public: null },
    ]);
  });
});

describe("meetings.conclude", () => {
  const MEETING = {
    id: "m1",
    organizationId: "org-1",
    kind: "board",
    title: "Board",
    startsAt: AT,
    status: "held",
    createdAt: AT,
    updatedAt: AT,
  };

  it("settles the decisions, then holds the meeting", async () => {
    const t = fieldsTransport({
      decide_meeting_decision: () => ({
        id: "d1",
        organizationId: "org-1",
        meetingId: "m1",
        title: "Budget",
        status: "passed",
        createdAt: AT,
      }),
      hold_meeting: () => MEETING,
    });

    const held = await createMeetings({ transport: t, tenant: "org-1" })
      .conclude({
        meetingId: "m1",
        summary: "Done",
        decisions: [{ decisionId: "d1", status: "passed" }],
      })
      .orThrow();

    expect(held.status).toBe("held");
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "decide_meeting_decision",
      "hold_meeting",
    ]);
  });
});

describe("enrollments.restart and advance", () => {
  const ENROLLMENT = {
    id: "e1",
    organizationId: "org-1",
    program: "onboarding",
    subjectType: "party",
    subjectId: "pa1",
    status: "active",
    steps: ["kickoff", "import"],
    completedSteps: 1,
    totalSteps: 2,
    enrolledAt: AT,
    updatedAt: AT,
    progress: [{ step: "kickoff", completedAt: AT }],
  };

  it("restart resets each completed step", async () => {
    const t = fieldsTransport({
      list_enrollments: () => [ENROLLMENT],
      reset_enrollment_step: () => ({
        ...ENROLLMENT,
        progress: [],
        completedSteps: 0,
      }),
    });

    const restarted = await createEnrollments({ transport: t, tenant: "org-1" })
      .restart("e1")
      .orThrow();

    expect(restarted.completedSteps).toBe(0);
    expect(t.calls[1]?.[1]).toMatchObject({ step: "kickoff" });
  });

  it("restart fails for an unknown enrollment", async () => {
    const t = fieldsTransport({ list_enrollments: () => [] });

    const result = await createEnrollments({
      transport: t,
      tenant: "org-1",
    }).restart("e9");

    expect(result.ok ? undefined : result.error.kind).toBe("not_found");
  });

  it("advance completes the first open step", async () => {
    const t = fieldsTransport({
      enrollment: () => ENROLLMENT,
      complete_enrollment_step: () => ENROLLMENT,
    });

    await createEnrollments({ transport: t, tenant: "org-1" })
      .advance({
        enrollmentId: "e1",
        program: "onboarding",
        subject: { type: "party", id: "pa1" },
      })
      .orThrow();

    expect(t.calls[1]?.[1]).toMatchObject({ step: "import" });
  });
});

describe("approvals.decideForSubject and guarded", () => {
  const REQUEST = {
    id: "r1",
    organizationId: "o",
    subjectType: "invoice",
    subjectId: "i1",
    action: "send",
    status: "pending",
    step: 0,
    steps: [],
    payload: {},
    createdAt: AT,
  };

  const subject = { type: "invoice", id: "i1" };

  it("decideForSubject finds the pending request by action", async () => {
    const t = fieldsTransport({
      list_approvals: () => [REQUEST],
      decide_approval: () => ({ ...REQUEST, status: "approved" }),
    });

    const approvals = createApprovals({
      transport: t,
      tenant: "o",
      approver: { userId: "u2", claims: { sub: "u2" } },
    });

    const approved = await approvals
      .decideForSubject({ subject, action: "send", decision: "approve" })
      .orThrow();

    expect(approved.status).toBe("approved");

    const missing = await approvals.decideForSubject({
      subject,
      action: "void",
      decision: "reject",
    });

    expect(missing.ok ? undefined : missing.error.kind).toBe("not_found");
  });

  it("guarded runs when approved and files a request otherwise", async () => {
    let approved = true;

    const t = fieldsTransport({
      is_approved: () => approved,
      request_approval: () => REQUEST,
    });

    const approvals = createApprovals({ transport: t, tenant: "o" });
    let ran = 0;

    const run = () => {
      ran += 1;

      return "sent";
    };

    expect(
      await approvals.guarded({ subject, action: "send", run }).orThrow(),
    ).toEqual({ ran: true, value: "sent" });

    approved = false;

    const filed = await approvals
      .guarded({ subject, action: "send", run })
      .orThrow();

    expect(filed.ran).toBe(false);
    expect(ran).toBe(1);
  });
});

describe("rank.between", () => {
  it("makes a key between two neighbors without a database call", async () => {
    const t = fieldsTransport({});
    const rank = createRank({ transport: t });
    const key = await rank.between({ previous: "a", next: "c" }).orThrow();

    expect(key > "a" && key < "c").toBe(true);
    expect(t.calls).toEqual([]);
  });
});

describe("inbox.conversations.reply and takeOver", () => {
  const CONVERSATION = {
    id: "c1",
    tenant_id: "org-1",
    inbox_id: "i1",
    contact_id: "k1",
    thread_id: "t1",
    status: "open",
    bot_mode: "human",
    created_at: AT,
  };

  it("takeOver switches to human mode, then assigns", async () => {
    const t = fieldsTransport({
      set_bot_mode: () => CONVERSATION,
      assign_conversation: () => CONVERSATION,
    });

    await createInbox({ transport: t })
      .conversations.takeOver({ conversationId: "c1", assigneeId: "u1" })
      .orThrow();

    expect(t.calls.map(([fn]) => fn)).toEqual([
      "set_bot_mode",
      "assign_conversation",
    ]);
  });
});

describe("automations.installDefaults", () => {
  it("copies the defaults for the organization", async () => {
    const t = fieldsTransport({ install_default_rules: () => 3 });

    const copied = await createAutomationsAdmin({ transport: t })
      .installDefaults({ organizationId: "org-1" })
      .orThrow();

    expect(copied).toBe(3);
    expect(t.calls[0]).toEqual(["install_default_rules", { tenant: "org-1" }]);
  });
});
