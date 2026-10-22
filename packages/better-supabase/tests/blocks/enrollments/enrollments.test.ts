import { describe, expect, it } from "vitest";

import {
  createEnrollments,
  enrollmentsBlock,
  enrollmentsEvents,
  enrollmentsSection,
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

describe("enrollmentsSection", () => {
  it("loads a record's enrollments", async () => {
    const fake = fakeTransport({ list_enrollments: [ENROLLMENT] });

    const enrollments = createEnrollments({
      transport: fake.transport,
      tenant: "org-1",
    });

    const list = await enrollmentsSection
      .load(enrollments, { type: "party", id: "pa1" }, undefined)
      .orThrow();

    expect(list).toHaveLength(1);
    expect(fake.calls[0]?.[1]).toMatchObject({
      subject_type: "party",
      subject_id: "pa1",
    });
    expect(enrollmentsBlock.sections).toEqual({
      enrollments: enrollmentsSection,
    });
    expect(enrollmentsSection.events).toContain("enrollment.completed");
    expect(enrollmentsEvents.types).toContain("enrollment_program.deleted");
  });
});
