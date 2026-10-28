import { describe, expect, it } from "vitest";

import {
  createEnrollments,
  enrollmentsBlock,
  enrollmentsEvents,
  enrollmentsBinding,
} from "../../../src/blocks/enrollments/index.ts";

const AT = "2026-10-22T10:00:00Z";

const PROGRAM = {
  id: "p1",
  organizationId: "org-1",
  key: "customer-onboarding",
  name: "Customer onboarding",
  description: null,
  subjectTypes: ["party"],
  steps: [{ id: "kickoff", title: "Kickoff call" }, { id: "import" }],
  enabled: true,
  version: 2,
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const ENROLLMENT = {
  id: "e1",
  organizationId: "org-1",
  program: "customer-onboarding",
  programVersion: 2,
  subjectType: "party",
  subjectId: "pa1",
  status: "active",
  steps: ["kickoff", "import"],
  completedSteps: 1,
  totalSteps: 2,
  enrolledBy: "u1",
  enrolledAt: AT,
  completedAt: null,
  cancelledAt: null,
  updatedAt: AT,
  progress: [{ step: "kickoff", completedAt: AT, completedBy: "u1" }],
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  };
}

describe("createEnrollments", () => {
  it("saves, lists and deletes programs", async () => {
    const fake = fakeTransport({
      save_enrollment_program: PROGRAM,
      enrollment_programs: [
        PROGRAM,
        {
          ...PROGRAM,
          id: "p2",
          description: "Training",
          enabled: false,
          version: null,
          createdBy: null,
          subjectTypes: null,
          steps: null,
        },
      ],
      delete_enrollment_program: true,
    });

    const enrollments = createEnrollments({
      transport: fake.transport,
      tenant: "org-1",
    });

    const saved = await enrollments
      .saveProgram({
        key: "customer-onboarding",
        name: "Customer onboarding",
        steps: [{ id: "kickoff" }],
      })
      .orThrow();

    expect(saved.createdAt).toBeInstanceOf(Temporal.Instant);
    expect(saved).toMatchObject({
      key: "customer-onboarding",
      subjectTypes: ["party"],
      steps: [{ id: "kickoff", title: "Kickoff call" }, { id: "import" }],
      enabled: true,
      version: 2,
      createdBy: "u1",
    });
    expect(saved).not.toHaveProperty("description");

    const programs = await enrollments.programs().orThrow();

    expect(programs[1]).toMatchObject({
      description: "Training",
      enabled: false,
      version: 1,
      subjectTypes: [],
      steps: [],
    });
    expect(programs[1]).not.toHaveProperty("createdBy");
    expect(await enrollments.deleteProgram("p2").orThrow()).toBe(true);

    expect(fake.calls).toEqual([
      [
        "save_enrollment_program",
        {
          tenant: "org-1",
          program: {
            key: "customer-onboarding",
            name: "Customer onboarding",
            steps: [{ id: "kickoff" }],
          },
        },
      ],
      ["enrollment_programs", { tenant: "org-1" }],
      ["delete_enrollment_program", { program_id: "p2" }],
    ]);
  });

  it("enrolls a subject and reads its enrollments", async () => {
    const fake = fakeTransport({
      enroll: ENROLLMENT,
      enrollment: null,
      list_enrollments: [
        ENROLLMENT,
        {
          ...ENROLLMENT,
          id: "e2",
          organizationId: null,
          programVersion: null,
          enrolledBy: null,
          status: "completed",
          completedSteps: null,
          totalSteps: null,
          steps: null,
          progress: null,
          completedAt: AT,
        },
      ],
    });

    const enrollments = createEnrollments({
      transport: fake.transport,
      tenant: "org-1",
    });

    const party = { type: "party", id: "pa1" };

    const enrollment = await enrollments
      .enroll("customer-onboarding", party)
      .orThrow();

    expect(enrollment).toMatchObject({
      subject: party,
      status: "active",
      programVersion: 2,
      completedSteps: 1,
      totalSteps: 2,
      progress: [{ step: "kickoff", completedBy: "u1" }],
    });
    expect(enrollment).not.toHaveProperty("completedAt");
    expect(
      await enrollments.enrollment("customer-onboarding", party).orThrow(),
    ).toBeNull();

    const list = await enrollments
      .list({
        program: "customer-onboarding",
        subject: party,
        status: "completed",
        pageSize: 10,
        before: Temporal.Instant.from(AT),
      })
      .orThrow();

    expect(list[1]).toMatchObject({
      status: "completed",
      completedSteps: 0,
      totalSteps: 0,
      steps: [],
      progress: [],
    });
    expect(list[1]).not.toHaveProperty("organizationId");
    expect(list[1]).not.toHaveProperty("programVersion");
    expect(list[1]?.completedAt).toBeInstanceOf(Temporal.Instant);
    await enrollments.list().orThrow();

    expect(fake.calls.slice(2)).toEqual([
      [
        "list_enrollments",
        {
          tenant: "org-1",
          program: "customer-onboarding",
          subject_type: "party",
          subject_id: "pa1",
          status: "completed",
          page_size: 10,
          before: "2026-10-22T10:00:00Z",
        },
      ],
      [
        "list_enrollments",
        {
          tenant: "org-1",
          program: null,
          subject_type: null,
          subject_id: null,
          status: null,
          page_size: null,
          before: null,
        },
      ],
    ]);
    expect(fake.calls[1]).toEqual([
      "enrollment",
      {
        tenant: "org-1",
        program: "customer-onboarding",
        subject_type: "party",
        subject_id: "pa1",
      },
    ]);
  });

  it("completes, resets and cancels steps", async () => {
    const fake = fakeTransport({
      complete_enrollment_step: { ...ENROLLMENT, status: "completed" },
      reset_enrollment_step: ENROLLMENT,
      cancel_enrollment: {
        ...ENROLLMENT,
        status: "cancelled",
        cancelledAt: AT,
      },
    });

    const enrollments = createEnrollments({ transport: fake.transport });

    expect((await enrollments.complete("e1", "import").orThrow()).status).toBe(
      "completed",
    );
    expect((await enrollments.reset("e1", "import").orThrow()).status).toBe(
      "active",
    );

    const cancelled = await enrollments.cancel("e1").orThrow();

    expect(cancelled.cancelledAt).toBeInstanceOf(Temporal.Instant);
    expect(fake.calls).toEqual([
      ["complete_enrollment_step", { enrollment_id: "e1", step: "import" }],
      ["reset_enrollment_step", { enrollment_id: "e1", step: "import" }],
      ["cancel_enrollment", { enrollment_id: "e1" }],
    ]);
  });

  it("reads step assignees, due dates and the schedule", async () => {
    const fake = fakeTransport({
      save_enrollment_program: {
        ...PROGRAM,
        steps: [
          {
            id: "kickoff",
            assignee: { role: "admin" },
            due: { days: 3, from: "start" },
          },
          {
            id: "import",
            assignee: { userId: "u2" },
            due: { days: -1, from: "end" },
          },
          { id: "review", assignee: {}, due: null },
        ],
      },
      enroll: { ...ENROLLMENT, startsAt: AT, endsAt: null, schedule: null },
      set_enrollment_dates: {
        ...ENROLLMENT,
        startsAt: AT,
        endsAt: "2026-11-01T00:00:00Z",
        schedule: [
          {
            step: "kickoff",
            assignee: { role: "admin" },
            dueAt: "2026-10-25T10:00:00Z",
          },
          { step: "import", assignee: { userId: "u2" }, completedAt: AT },
        ],
      },
    });

    const enrollments = createEnrollments({
      transport: fake.transport,
      tenant: "org-1",
    });

    const program = await enrollments
      .saveProgram({ key: "customer-onboarding" })
      .orThrow();

    expect(program.steps).toEqual([
      {
        id: "kickoff",
        assignee: { role: "admin" },
        due: { days: 3, from: "start" },
      },
      {
        id: "import",
        assignee: { userId: "u2" },
        due: { days: -1, from: "end" },
      },
      { id: "review" },
    ]);

    const party = { type: "party", id: "pa1" };

    const plain = await enrollments
      .enroll("customer-onboarding", party)
      .orThrow();

    expect(plain.schedule).toEqual([]);
    expect(plain.startsAt).toBeInstanceOf(Temporal.Instant);
    expect(plain).not.toHaveProperty("endsAt");

    const dated = await enrollments
      .enroll("customer-onboarding", party, {
        endsAt: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      })
      .orThrow();

    expect(dated.endsAt?.toString()).toBe("2026-11-01T00:00:00Z");
    expect(dated.schedule[0]?.dueAt?.toString()).toBe("2026-10-25T10:00:00Z");
    expect(dated.schedule[1]).toMatchObject({
      step: "import",
      assignee: { userId: "u2" },
    });
    expect(dated.schedule[1]).not.toHaveProperty("dueAt");

    await enrollments
      .setDates("e1", { startsAt: Temporal.Instant.from(AT), endsAt: null })
      .orThrow();

    expect(fake.calls.slice(2)).toEqual([
      [
        "enroll",
        {
          tenant: "org-1",
          program: "customer-onboarding",
          subject_type: "party",
          subject_id: "pa1",
        },
      ],
      [
        "set_enrollment_dates",
        { enrollment_id: "e1", dates: { endsAt: "2026-11-01T00:00:00Z" } },
      ],
      [
        "set_enrollment_dates",
        {
          enrollment_id: "e1",
          dates: { startsAt: "2026-10-22T10:00:00Z", endsAt: null },
        },
      ],
    ]);
  });

  it("rejects an unknown due date anchor", async () => {
    const enrollments = createEnrollments({
      transport: fakeTransport({
        enrollment_programs: [
          {
            ...PROGRAM,
            steps: [{ id: "kickoff", due: { days: 1, from: "later" } }],
          },
        ],
      }).transport,
      tenant: "org-1",
    });

    expect((await enrollments.programs()).ok).toBe(false);
  });

  it("lists open steps", async () => {
    const fake = fakeTransport({
      open_enrollment_steps: [
        {
          id: "e1",
          organizationId: "org-1",
          program: "customer-onboarding",
          subjectType: "party",
          subjectId: "pa1",
          step: "kickoff",
          title: "Kickoff call",
          assignee: { role: "admin" },
          dueAt: AT,
        },
        {
          id: "e2",
          organizationId: "org-1",
          program: "customer-onboarding",
          subjectType: "party",
          subjectId: "pa2",
          step: "import",
        },
      ],
    });

    const enrollments = createEnrollments({
      transport: fake.transport,
      tenant: "org-1",
    });

    const open = await enrollments
      .openSteps({
        role: "admin",
        userId: "u2",
        dueBefore: Temporal.Instant.from(AT),
        pageSize: 10,
      })
      .orThrow();

    expect(open[0]).toMatchObject({
      enrollmentId: "e1",
      subject: { type: "party", id: "pa1" },
      title: "Kickoff call",
      assignee: { role: "admin" },
    });
    expect(open[0]?.dueAt).toBeInstanceOf(Temporal.Instant);
    expect(open[1]).not.toHaveProperty("assignee");
    expect(open[1]).not.toHaveProperty("dueAt");
    await enrollments.openSteps().orThrow();

    expect(fake.calls).toEqual([
      [
        "open_enrollment_steps",
        {
          tenant: "org-1",
          assignee_role: "admin",
          assignee_user: "u2",
          due_before: "2026-10-22T10:00:00Z",
          page_size: 10,
        },
      ],
      [
        "open_enrollment_steps",
        {
          tenant: "org-1",
          assignee_role: null,
          assignee_user: null,
          due_before: null,
          page_size: null,
        },
      ],
    ]);
  });

  it("rejects an unknown status from the database", async () => {
    const enrollments = createEnrollments({
      transport: fakeTransport({
        cancel_enrollment: { ...ENROLLMENT, status: "paused" },
      }).transport,
    });

    expect((await enrollments.cancel("e1")).ok).toBe(false);
  });

  it("fails tenant-scoped calls without a tenant", async () => {
    const fake = fakeTransport({});
    const enrollments = createEnrollments({ transport: fake.transport });

    expect((await enrollments.programs()).ok).toBe(false);
    expect(
      (await enrollments.enroll("p", { type: "party", id: "pa1" })).ok,
    ).toBe(false);
    expect((await enrollments.list()).ok).toBe(false);
    expect(fake.calls).toEqual([]);
  });
});

describe("enrollmentsBinding", () => {
  it("loads a record's enrollments", async () => {
    const fake = fakeTransport({ list_enrollments: [ENROLLMENT] });

    const enrollments = createEnrollments({
      transport: fake.transport,
      tenant: "org-1",
    });

    const list = await enrollmentsBinding
      .load(enrollments, { type: "party", id: "pa1" }, undefined)
      .orThrow();

    expect(list).toHaveLength(1);
    expect(fake.calls[0]?.[1]).toMatchObject({
      subject_type: "party",
      subject_id: "pa1",
    });
    expect(enrollmentsBlock.record).toBe(enrollmentsBinding);
    expect(enrollmentsBinding.events).toContain("enrollment.completed");
    expect(enrollmentsEvents.types).toContain("enrollment_program.deleted");
  });
});
