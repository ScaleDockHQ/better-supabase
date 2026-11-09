import { describe, expect, it } from "vitest";

import { createCarePlans } from "../../src/blocks/care-plans/care-plans.ts";

const STAMP = "2026-11-01T00:00:00Z";

const plan = {
  id: "p1",
  organizationId: "org-1",
  subjectType: "resident",
  subjectId: "r1",
  title: "Plan",
  status: "draft",
  version: 1,
  createdAt: STAMP,
  updatedAt: STAMP,
};

const problem = {
  id: "pr1",
  planId: "p1",
  codeSystem: "snomed",
  title: "Pain",
  status: "active",
  rank: "a",
  createdAt: STAMP,
  updatedAt: STAMP,
};

const goal = {
  id: "g1",
  planId: "p1",
  problemId: "pr1",
  title: "Walk",
  status: "planned",
  rank: "a",
  createdAt: STAMP,
  updatedAt: STAMP,
};

const action = {
  id: "a1",
  planId: "p1",
  goalId: "g1",
  kind: "task",
  title: "Walk daily",
  status: "planned",
  rank: "a",
  createdAt: STAMP,
  updatedAt: STAMP,
};

function transport(fail?: string) {
  const rows: Record<string, unknown> = {
    create_care_plan: plan,
    add_care_plan_problem: problem,
    add_care_plan_goal: goal,
    add_care_plan_action: action,
    get_care_plan: plan,
    list_care_plans: [plan, { ...plan, id: "p2" }],
    due_care_plan_reviews: 2,
  };

  return {
    call(_schema: string, fn: string, _args: Record<string, unknown>) {
      if (fn === fail) {
        return Promise.reject(new Error(fn));
      }

      return Promise.resolve(rows[fn]);
    },
  };
}

const tree = {
  plan: { subjectType: "resident", subjectId: "r1", title: "Plan" },
  problems: [
    { title: "Pain" },
    {
      title: "Falls",
      goals: [
        { title: "Stand" },
        { title: "Walk", actions: [{ title: "Walk daily" }] },
      ],
    },
  ],
};

describe("care plan client", () => {
  it("builds a tree and stops at the first failed step", async () => {
    const saved = await createCarePlans({
      transport: transport(),
      tenant: "org-1",
    }).createTree(tree);

    expect(saved.ok ? saved.data.id : saved.error.message).toBe("p1");

    const created = await createCarePlans({
      transport: transport("create_care_plan"),
      tenant: "org-1",
    }).createTree(tree);

    expect(created.ok).toBe(false);

    const problemFailed = await createCarePlans({
      transport: transport("add_care_plan_problem"),
      tenant: "org-1",
    }).createTree(tree);

    expect(problemFailed.ok).toBe(false);

    const goalFailed = await createCarePlans({
      transport: transport("add_care_plan_goal"),
      tenant: "org-1",
    }).createTree(tree);

    expect(goalFailed.ok).toBe(false);

    const actionFailed = await createCarePlans({
      transport: transport("add_care_plan_action"),
      tenant: "org-1",
    }).createTree(tree);

    expect(actionFailed.ok).toBe(false);
  });

  it("limits a list and counts due reviews", async () => {
    const plans = createCarePlans({ transport: transport(), tenant: "org-1" });

    const listed = await plans.list({
      subjectType: "resident",
      subjectId: "r1",
      limit: 1,
    });

    const all = await plans.list({ subjectType: "resident", subjectId: "r1" });

    const due = await plans.dueReviews();

    expect(listed.ok ? listed.data : []).toHaveLength(1);
    expect(all.ok ? all.data : []).toHaveLength(2);
    expect(due.ok ? due.data : 0).toBe(2);
  });
});
