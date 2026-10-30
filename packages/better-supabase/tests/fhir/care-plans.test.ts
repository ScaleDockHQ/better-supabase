import { describe, expect, it } from "vitest";

import type {
  FhirCarePlanSource,
  FhirGoalSource,
} from "../../src/fhir/care-plans.ts";

import { toFhirCarePlan, toFhirGoal } from "../../src/fhir/care-plans.ts";

const ACHIEVEMENT = "http://terminology.hl7.org/CodeSystem/goal-achievement";
const CLINICAL = "http://terminology.hl7.org/CodeSystem/condition-clinical";

const plan: FhirCarePlanSource = {
  id: "plan-1",
  subjectId: "client-1",
  title: "Mobility",
  status: "active",
  createdAt: Temporal.Instant.from("2026-10-01T09:00:00Z"),
  startsOn: Temporal.PlainDate.from("2026-10-02"),
  ownerId: "user-1",
  problems: [
    {
      id: "problem-1",
      codeSystem: "icf",
      code: "d450",
      title: "Walking",
      status: "active",
      description: "Falls twice a month",
      goals: [
        {
          id: "goal-1",
          problemId: "problem-1",
          title: "Walk 100 m unaided",
          status: "in_progress",
          targetOn: Temporal.PlainDate.from("2026-12-01"),
          measure: {
            code: "walk-distance",
            system: "urn:app",
            target: 100,
            unit: "m",
          },
          actions: [
            {
              id: "action-1",
              goalId: "goal-1",
              kind: "intervention",
              title: "Physiotherapy",
              status: "active",
              instructions: "Twice a week",
              frequency: { frequency: 2, period: 1, periodUnit: "wk" },
              startsOn: Temporal.PlainDate.from("2026-10-02"),
            },
            {
              id: "action-2",
              goalId: "goal-1",
              kind: "appointment",
              title: "Review",
              status: "planned",
              startsOn: Temporal.PlainDate.from("2026-11-01"),
              endsOn: Temporal.PlainDate.from("2026-11-01"),
            },
            {
              id: "action-3",
              goalId: "goal-1",
              kind: "task",
              title: "Order walker",
              status: "ended",
              endReason: "delivered",
            },
            {
              id: "action-4",
              goalId: "goal-1",
              kind: "measure",
              title: "Weekly distance",
              status: "planned",
              frequency: { frequency: 1, period: 1, periodUnit: "wk" },
            },
          ],
        },
      ],
    },
    {
      id: "problem-2",
      codeSystem: "custom",
      title: "Loneliness",
      status: "resolved",
      goals: [],
    },
  ],
};

describe("toFhirCarePlan", () => {
  it("contains the problems and goals, and maps actions to activities", () => {
    const resource = toFhirCarePlan(plan, {
      codeSystems: { icf: "http://hl7.org/fhir/sid/icf-nl" },
      user: (id) => ({ reference: `Practitioner/${id}` }),
    });

    expect(resource).toMatchObject({
      resourceType: "CarePlan",
      id: "plan-1",
      status: "active",
      intent: "plan",
      title: "Mobility",
      subject: { reference: "Patient/client-1" },
      period: { start: "2026-10-02" },
      created: "2026-10-01T09:00:00Z",
      author: { reference: "Practitioner/user-1" },
      addresses: [{ reference: "#problem-1" }, { reference: "#problem-2" }],
      goal: [{ reference: "#goal-1" }],
    });
    expect(resource.contained).toEqual([
      {
        resourceType: "Condition",
        id: "problem-1",
        clinicalStatus: { coding: [{ system: CLINICAL, code: "active" }] },
        code: {
          coding: [
            {
              system: "http://hl7.org/fhir/sid/icf-nl",
              code: "d450",
              display: "Walking",
            },
          ],
          text: "Walking",
        },
        subject: { reference: "Patient/client-1" },
        note: [{ text: "Falls twice a month" }],
      },
      {
        resourceType: "Condition",
        id: "problem-2",
        clinicalStatus: { coding: [{ system: CLINICAL, code: "resolved" }] },
        code: { text: "Loneliness" },
        subject: { reference: "Patient/client-1" },
      },
      {
        resourceType: "Goal",
        id: "goal-1",
        lifecycleStatus: "active",
        achievementStatus: {
          coding: [{ system: ACHIEVEMENT, code: "in-progress" }],
        },
        description: { text: "Walk 100 m unaided" },
        subject: { reference: "Patient/client-1" },
        target: [
          {
            measure: { coding: [{ system: "urn:app", code: "walk-distance" }] },
            detailQuantity: { value: 100, unit: "m" },
            dueDate: "2026-12-01",
          },
        ],
        addresses: [{ reference: "#problem-1" }],
      },
    ]);
    expect(resource.activity).toEqual([
      {
        detail: {
          code: { text: "Physiotherapy" },
          goal: [{ reference: "#goal-1" }],
          status: "in-progress",
          scheduledTiming: {
            repeat: {
              frequency: 2,
              period: 1,
              periodUnit: "wk",
              boundsPeriod: { start: "2026-10-02" },
            },
          },
          description: "Twice a week",
        },
      },
      {
        detail: {
          kind: "Appointment",
          code: { text: "Review" },
          goal: [{ reference: "#goal-1" }],
          status: "not-started",
          scheduledPeriod: { start: "2026-11-01", end: "2026-11-01" },
        },
      },
      {
        detail: {
          kind: "Task",
          code: { text: "Order walker" },
          goal: [{ reference: "#goal-1" }],
          status: "completed",
          statusReason: { text: "delivered" },
        },
      },
      {
        detail: {
          code: { text: "Weekly distance" },
          goal: [{ reference: "#goal-1" }],
          status: "not-started",
          scheduledTiming: {
            repeat: { frequency: 1, period: 1, periodUnit: "wk" },
          },
        },
      },
    ]);
  });

  it("leaves out empty lists, and maps draft and archived plans", () => {
    const { startsOn: _startsOn, ownerId: _ownerId, ...rest } = plan;
    const empty = { ...rest, status: "draft", problems: [] } as const;
    const draft = toFhirCarePlan(empty);

    expect(draft).toEqual({
      resourceType: "CarePlan",
      id: "plan-1",
      status: "draft",
      intent: "plan",
      title: "Mobility",
      subject: { reference: "Patient/client-1" },
      created: "2026-10-01T09:00:00Z",
    });
    expect(toFhirCarePlan({ ...empty, status: "archived" }).status).toBe(
      "completed",
    );
  });
});

describe("toFhirGoal", () => {
  const goal: FhirGoalSource = {
    id: "goal-2",
    problemId: "problem-1",
    title: "Sleep through",
    status: "planned",
  };

  it.each([
    ["planned", "planned", undefined],
    ["achieved", "completed", "achieved"],
    ["not_achieved", "completed", "not-achieved"],
    ["canceled", "cancelled", undefined],
  ] as const)("maps a %s goal", (status, lifecycle, achievement) => {
    const resource = toFhirGoal({ ...goal, status }, "client-1");

    expect(resource.lifecycleStatus).toBe(lifecycle);
    expect(resource.achievementStatus).toEqual(
      achievement === undefined
        ? undefined
        : { coding: [{ system: ACHIEVEMENT, code: achievement }] },
    );
    expect(resource.addresses).toEqual([{ reference: "Condition/problem-1" }]);
    expect(resource.target).toBeUndefined();
  });

  it("takes the subject and the problem from options, and text or flag targets", () => {
    const resource = toFhirGoal(
      { ...goal, measure: { target: "independent" } },
      "client-1",
      {
        subject: { reference: "Patient/p-9" },
        addresses: { reference: "Condition/c-9" },
      },
    );

    expect(resource.subject).toEqual({ reference: "Patient/p-9" });
    expect(resource.addresses).toEqual([{ reference: "Condition/c-9" }]);
    expect(resource.target).toEqual([{ detailString: "independent" }]);
    expect(
      toFhirGoal({ ...goal, measure: { code: "x", target: true } }, "client-1")
        .target,
    ).toEqual([{ measure: { coding: [{ code: "x" }] }, detailBoolean: true }]);
    expect(
      toFhirGoal({ ...goal, measure: { target: 5 } }, "client-1").target,
    ).toEqual([{ detailQuantity: { value: 5 } }]);
  });
});
