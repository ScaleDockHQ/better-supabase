import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  carePlanActionInputSchema,
  carePlanGoalInputSchema,
  carePlanInputSchema,
  carePlanProblemInputSchema,
  carePlansBlock,
  carePlansEvents,
  createCarePlans,
} from "../../../src/blocks/care-plans/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-30T09:00:00Z";
const ID = "00000000-0000-4000-8000-000000000001";

const ACTION = {
  id: "a1",
  planId: "p1",
  goalId: "g1",
  kind: "measure",
  title: "Bed rail at night",
  status: "planned",
  requiresApproval: true,
  rank: "a0",
  createdAt: AT,
  updatedAt: AT,
  instructions: "Raise after 22:00",
  frequency: { frequency: 1, period: 1, periodUnit: "d" },
  teamRole: "nurse",
  measureKind: "physical",
  approvalId: "ap1",
  reviewEvery: "P0Y1M0DT0H0M0S",
  startsOn: "2026-11-01",
  endsOn: "2027-05-01",
};

const BARE_ACTION = {
  id: "a2",
  planId: "p1",
  goalId: "g1",
  kind: "intervention",
  title: "Walk daily",
  status: "active",
  rank: "a1",
  createdAt: AT,
  updatedAt: AT,
  frequency: "not an object",
  startedAt: AT,
};

const GOAL = {
  id: "g1",
  planId: "p1",
  problemId: "pr1",
  title: "Sleeps safely",
  status: "in_progress",
  rank: "a0",
  createdAt: AT,
  updatedAt: AT,
  targetOn: "2027-01-01",
  measure: { target: 0, code: "falls" },
  actions: [ACTION, BARE_ACTION, "skipped"],
};

const PROBLEM = {
  id: "pr1",
  planId: "p1",
  codeSystem: "icnp",
  code: "10029395",
  title: "Risk of falls",
  description: "Fell twice",
  status: "active",
  rank: "a0",
  createdAt: AT,
  updatedAt: AT,
  goals: [GOAL],
};

const EVALUATION = {
  id: "e1",
  planId: "p1",
  goalId: "g1",
  status: "achieved",
  evaluatedAt: AT,
  outcome: "No falls",
  submissionId: "s1",
  authorId: "u1",
};

const PLAN = {
  id: "p1",
  organizationId: "org-1",
  subjectType: "contact",
  subjectId: "c1",
  title: "Care plan",
  status: "active",
  version: 2,
  createdAt: AT,
  updatedAt: AT,
  startsOn: "2026-11-01",
  reviewOn: "2027-05-01",
  ownerId: "u1",
  signatureRequestId: "sr1",
  agreedAt: AT,
  publishedVersionId: "v1",
  publishedAt: AT,
  publishedBy: "u1",
  createdBy: "u1",
  fields: { ward: "north" },
  problems: [PROBLEM],
  evaluations: [EVALUATION],
};

const DRAFT = {
  id: "p2",
  organizationId: "org-1",
  subjectType: "contact",
  subjectId: "c1",
  title: "Draft",
  status: "draft",
  version: "3",
  createdAt: AT,
  updatedAt: AT,
  fields: { ward: "south" },
};

const Fields = v.object({ ward: v.picklist(["north", "south"]) });

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createCarePlans", () => {
  it("creates and updates a plan with its extra fields and checks them", async () => {
    const t = fieldsTransport({
      create_care_plan: () => PLAN,
      update_care_plan: () => DRAFT,
    });

    const plans = createCarePlans({
      transport: t,
      tenant: "org-1",
      fields: Fields,
    });

    const created = await plans
      .create({
        subjectType: "contact",
        subjectId: "c1",
        title: "Care plan",
        startsOn: Temporal.PlainDate.from("2026-11-01"),
        reviewOn: null,
        fields: { ward: "north" },
      })
      .orThrow();

    const updated = await plans
      .update({ planId: "p2", change: { title: "Draft" } })
      .orThrow();

    const refused = await plans.create({
      subjectType: "contact",
      subjectId: "c1",
      title: "Bad",
      // SAFETY: a value the schema refuses, to prove the client checks it.
      fields: { ward: "east" } as unknown as { ward: "north" },
    });

    expect(created.fields.ward).toBe("north");
    expect(created.version).toBe(2);
    expect(created.reviewOn?.toString()).toBe("2027-05-01");
    expect(created.agreedAt?.toString()).toBe("2026-10-30T09:00:00Z");
    expect(created.evaluations[0]).toEqual({
      ...EVALUATION,
      evaluatedAt: Temporal.Instant.from(AT),
    });

    const [problem] = created.problems;
    const [goal] = problem?.goals ?? [];
    const [measure, walk] = goal?.actions ?? [];
    expect(problem).toMatchObject({
      code: "10029395",
      description: "Fell twice",
    });
    expect(goal?.targetOn?.toString()).toBe("2027-01-01");
    expect(goal?.actions).toHaveLength(2);
    expect(measure?.reviewEvery?.months).toBe(1);
    expect(measure?.endsOn?.toString()).toBe("2027-05-01");
    expect(measure).toMatchObject({
      requiresApproval: true,
      measureKind: "physical",
      approvalId: "ap1",
    });
    expect(walk?.frequency).toBeUndefined();
    expect(walk?.requiresApproval).toBe(false);
    expect(walk?.startedAt?.toString()).toBe("2026-10-30T09:00:00Z");

    expect(updated.version).toBe(3);
    expect(updated.problems).toEqual([]);
    expect(updated.ownerId).toBeUndefined();
    expect(refused.ok ? undefined : refused.error.kind).toBe("validation");
    expect(t.calls).toEqual([
      [
        "create_care_plan",
        {
          tenant: "org-1",
          input: {
            subjectType: "contact",
            subjectId: "c1",
            title: "Care plan",
            startsOn: "2026-11-01",
            reviewOn: null,
            fields: { ward: "north" },
          },
        },
      ],
      ["update_care_plan", { plan_id: "p2", changes: { title: "Draft" } }],
    ]);
  });

  it("builds the tree of problems, goals and actions", async () => {
    const t = fieldsTransport({
      add_care_plan_problem: () => PROBLEM,
      update_care_plan_problem: () => ({ ...PROBLEM, status: "resolved" }),
      add_care_plan_goal: () => GOAL,
      update_care_plan_goal: () => ({ ...GOAL, actions: undefined }),
      add_care_plan_action: () => ACTION,
      update_care_plan_action: () => BARE_ACTION,
    });

    const plans = createCarePlans({ transport: t });

    await plans
      .addProblem({ planId: "p1", input: { title: "Risk of falls" } })
      .orThrow();

    const resolved = await plans
      .updateProblem({ problemId: "pr1", change: { status: "resolved" } })
      .orThrow();

    await plans
      .addGoal({
        problemId: "pr1",
        input: {
          title: "Sleeps safely",
          targetOn: Temporal.PlainDate.from("2027-01-01"),
        },
      })
      .orThrow();

    const goal = await plans
      .updateGoal({ goalId: "g1", change: { status: "in_progress" } })
      .orThrow();

    await plans
      .addAction({
        goalId: "g1",
        input: {
          kind: "measure",
          title: "Bed rail at night",
          reviewEvery: Temporal.Duration.from({ months: 1 }),
        },
      })
      .orThrow();
    await plans.updateAction({ actionId: "a2", change: {} }).orThrow();

    expect(resolved.status).toBe("resolved");
    expect(goal.actions).toEqual([]);
    expect(t.calls).toEqual([
      [
        "add_care_plan_problem",
        { plan_id: "p1", input: { title: "Risk of falls" } },
      ],
      [
        "update_care_plan_problem",
        { problem_id: "pr1", changes: { status: "resolved" } },
      ],
      [
        "add_care_plan_goal",
        {
          problem_id: "pr1",
          input: { title: "Sleeps safely", targetOn: "2027-01-01" },
        },
      ],
      [
        "update_care_plan_goal",
        { goal_id: "g1", changes: { status: "in_progress" } },
      ],
      [
        "add_care_plan_action",
        {
          goal_id: "g1",
          input: {
            kind: "measure",
            title: "Bed rail at night",
            reviewEvery: "P1M",
          },
        },
      ],
      ["update_care_plan_action", { action_id: "a2", changes: {} }],
    ]);
  });

  it("publishes, archives, reads and lists plans", async () => {
    const t = fieldsTransport({
      publish_care_plan: () => PLAN,
      archive_care_plan: () => ({
        ...PLAN,
        status: "archived",
        archivedAt: AT,
      }),
      get_care_plan: () => PLAN,
      list_care_plans: () => [PLAN, DRAFT],
    });

    const plans = createCarePlans({ transport: t });

    await plans.publish("p1").orThrow();
    const archived = await plans.archive("p1").orThrow();
    const read = await plans.get("p1").orThrow();
    await plans.list({ subjectType: "contact", subjectId: "c1" }).orThrow();

    const all = await plans
      .list({ subjectType: "contact", subjectId: "c1", includeArchived: true })
      .orThrow();

    expect(archived.archivedAt?.toString()).toBe("2026-10-30T09:00:00Z");
    expect(read.publishedVersionId).toBe("v1");
    expect(all.map((plan) => plan.status)).toEqual(["active", "draft"]);
    expect(t.calls).toEqual([
      ["publish_care_plan", { plan_id: "p1" }],
      ["archive_care_plan", { plan_id: "p1" }],
      ["get_care_plan", { plan_id: "p1" }],
      [
        "list_care_plans",
        { subject_type: "contact", subject_id: "c1", include_archived: false },
      ],
      [
        "list_care_plans",
        { subject_type: "contact", subject_id: "c1", include_archived: true },
      ],
    ]);
  });

  it("evaluates goals and runs actions", async () => {
    const t = fieldsTransport({
      record_care_plan_evaluation: () => ({
        ...EVALUATION,
        outcome: undefined,
      }),
      start_care_plan_action: () => ACTION,
      end_care_plan_action: () => ({
        ...BARE_ACTION,
        status: "ended",
        endedAt: AT,
        endReason: "done",
      }),
      review_care_plan_action: () => ({ ...BARE_ACTION, reviewedAt: AT }),
    });

    const plans = createCarePlans({ transport: t });

    const evaluation = await plans
      .evaluate({ goalId: "g1", input: { status: "achieved" } })
      .orThrow();

    await plans
      .evaluate({
        goalId: "g1",
        input: { status: "achieved", outcome: "No falls", submissionId: "s1" },
      })
      .orThrow();
    await plans.startAction("a1").orThrow();

    const ended = await plans
      .endAction({ actionId: "a2", reason: "done" })
      .orThrow();

    await plans.endAction({ actionId: "a2" }).orThrow();

    const reviewed = await plans
      .reviewAction({ actionId: "a2", note: "Fine" })
      .orThrow();

    await plans.reviewAction({ actionId: "a2" }).orThrow();

    expect(evaluation.outcome).toBeUndefined();
    expect(ended).toMatchObject({ status: "ended", endReason: "done" });
    expect(reviewed.reviewedAt?.toString()).toBe("2026-10-30T09:00:00Z");
    expect(t.calls).toEqual([
      [
        "record_care_plan_evaluation",
        {
          goal_id: "g1",
          status: "achieved",
          outcome: null,
          submission_id: null,
        },
      ],
      [
        "record_care_plan_evaluation",
        {
          goal_id: "g1",
          status: "achieved",
          outcome: "No falls",
          submission_id: "s1",
        },
      ],
      ["start_care_plan_action", { action_id: "a1" }],
      ["end_care_plan_action", { action_id: "a2", reason: "done" }],
      ["end_care_plan_action", { action_id: "a2", reason: null }],
      ["review_care_plan_action", { action_id: "a2", note: "Fine" }],
      ["review_care_plan_action", { action_id: "a2", note: null }],
    ]);
  });

  it("lists measures, asks agreement and reports due reviews", async () => {
    const t = fieldsTransport({
      list_care_plan_measures: () => [
        {
          ...ACTION,
          planTitle: "Care plan",
          planStatus: "active",
          subjectType: "contact",
          subjectId: "c1",
        },
      ],
      request_care_plan_agreement: () => PLAN,
      due_care_plan_reviews: () => "3",
    });

    const plans = createCarePlans({ transport: t, tenant: "org-1" });

    const measures = await plans.measures().orThrow();
    await plans.measures({ activeOnly: false }).orThrow();

    const agreed = await plans
      .requestAgreement({ planId: "p1", signers: ["u2"] })
      .orThrow();

    await plans
      .requestAgreement({
        planId: "p1",
        signers: ["u2"],
        message: "Please agree",
      })
      .orThrow();
    const due = await plans.dueReviews().orThrow();

    expect(measures[0]).toMatchObject({
      planTitle: "Care plan",
      kind: "measure",
    });
    expect(agreed.signatureRequestId).toBe("sr1");
    expect(due).toBe(3);
    expect(t.calls).toEqual([
      ["list_care_plan_measures", { tenant: "org-1", active_only: true }],
      ["list_care_plan_measures", { tenant: "org-1", active_only: false }],
      [
        "request_care_plan_agreement",
        { plan_id: "p1", signers: ["u2"], message: null },
      ],
      [
        "request_care_plan_agreement",
        { plan_id: "p1", signers: ["u2"], message: "Please agree" },
      ],
      ["due_care_plan_reviews", {}],
    ]);
  });

  it("needs a tenant and rejects a malformed row", async () => {
    const t = fieldsTransport({
      get_care_plan: () => ({ ...PLAN, status: "open" }),
      due_care_plan_reviews: () => null,
    });

    const plans = createCarePlans({ transport: t });

    const untenanted = await plans.measures();
    const malformed = await plans.get("p1");

    expect(untenanted.ok).toBe(false);
    expect(malformed.ok).toBe(false);
    expect(await plans.dueReviews().orThrow()).toBe(0);
  });

  it("runs the hooks", async () => {
    const seen: string[] = [];

    const plans = createCarePlans({
      transport: fieldsTransport({ due_care_plan_reviews: () => 0 }),
      logger: console,
      hooks: {
        dueReviews: {
          after: () => {
            seen.push("dueReviews");
          },
        },
      },
    });

    await plans.dueReviews().orThrow();

    expect(seen).toEqual(["dueReviews"]);
  });
});

describe("care-plans block", () => {
  it("names the block, its events and validates the inputs", () => {
    expect(carePlansBlock.name).toBe("care-plans");
    expect(carePlansEvents.types).toContain("care_plan.published");
    expect(
      validate(carePlanInputSchema, {
        subjectType: "contact",
        subjectId: "c1",
        title: "Plan",
        copyFromPlanId: ID,
      }).issues,
    ).toBeUndefined();
    expect(
      validate(carePlanInputSchema, {
        subjectType: "",
        subjectId: "c1",
        title: "Plan",
      }).issues,
    ).toBeDefined();
    expect(
      validate(carePlanProblemInputSchema, { title: "Risk of falls" }).issues,
    ).toBeUndefined();
    expect(
      validate(carePlanGoalInputSchema, {
        title: "Sleeps",
        measure: { target: 1 },
      }).issues,
    ).toBeUndefined();
    expect(
      validate(carePlanActionInputSchema, {
        kind: "measure",
        title: "Bed rail",
      }).issues,
    ).toBeUndefined();
    expect(
      validate(carePlanActionInputSchema, { kind: "visit", title: "Bed rail" })
        .issues,
    ).toBeDefined();
  });
});
