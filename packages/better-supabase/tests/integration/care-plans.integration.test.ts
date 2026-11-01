import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createApprovals } from "../../src/blocks/approvals/index.ts";
import { createCarePlans } from "../../src/blocks/care-plans/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const TABLES = `create schema care_plans_it;
create table care_plans_it.clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text not null
);`;

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "subjects",
  "versions",
  "state-machine",
  "approvals",
  "care-plans",
];

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects(
    { client: { table: "care_plans_it.clients", idType: "uuid" } },
    ["care-plans"],
    {},
  ),
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("care-plans", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("drafts, publishes and evaluates a plan, and approves a measure", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const lead = await s.user("lead");
      const carer = await s.user("carer");
      const outsider = await s.user("outsider");
      await s.client.query(TABLES);
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { admin: lead, member: carer });
      await s.organization(outsider);

      const [client] = await s.rows<{ id: string }>(
        "insert into care_plans_it.clients (organization_id, name) values ($1, 'Ada') returning id",
        [org],
      );

      const subject = { subjectType: "client", subjectId: client?.id ?? "" };
      const transport = sqlTransport(s.sql);
      const plans = createCarePlans({ transport, tenant: org });
      const approvals = createApprovals({ transport });

      await s.as(owner);

      const draft = await plans
        .create({ ...subject, title: "Support plan" })
        .orThrow();

      expect(draft).toMatchObject({ status: "draft", version: 1 });

      const problem = await plans
        .addProblem({
          planId: draft.id,
          input: { code: "25", title: "Risk of falls" },
        })
        .orThrow();

      const goal = await plans
        .addGoal({
          problemId: problem.id,
          input: { title: "Walks with a frame" },
        })
        .orThrow();

      const walk = await plans
        .addAction({
          goalId: goal.id,
          input: {
            title: "Walk twice a day",
            reviewEvery: Temporal.Duration.from({ months: 1 }),
          },
        })
        .orThrow();

      const rail = await plans
        .addAction({
          goalId: goal.id,
          input: {
            kind: "measure",
            measureKind: "bed_rails",
            title: "Bed rail at night",
          },
        })
        .orThrow();

      expect(rail.requiresApproval).toBe(true);
      expect(
        await plans
          .evaluate({ goalId: goal.id, input: { status: "achieved" } })
          .then(hint),
      ).toBe("CARE_PLAN_INVALID");

      await s.as(carer);
      expect(
        await plans.create({ ...subject, title: "Other" }).then(hint),
      ).toBe("CARE_PLAN_FORBIDDEN");

      await s.as(owner);

      const active = await plans.publish(draft.id).orThrow();
      const actions = active.problems[0]?.goals[0]?.actions ?? [];

      expect(active.status).toBe("active");
      expect(active.publishedVersionId).toBeDefined();
      expect(actions.find((row) => row.id === walk.id)?.status).toBe("active");
      const asked = actions.find((row) => row.id === rail.id);

      expect(asked?.status).toBe("planned");
      expect(asked?.approvalId).toBeDefined();
      expect(
        await plans
          .updateProblem({ problemId: problem.id, change: { title: "Other" } })
          .then(hint),
      ).toBe("CARE_PLAN_NOT_DRAFT");
      expect(await plans.startAction(rail.id).then(hint)).toBe(
        "CARE_PLAN_ACTION_APPROVAL_REQUIRED",
      );

      await s.as(lead);
      await approvals.approve({ id: asked?.approvalId ?? "" }).orThrow();
      expect(await plans.measures().orThrow()).toEqual([
        expect.objectContaining({ id: rail.id, status: "active" }),
      ]);

      const evaluation = await plans
        .evaluate({
          goalId: goal.id,
          input: { status: "in_progress", outcome: "To the door" },
        })
        .orThrow();

      expect(evaluation.status).toBe("in_progress");

      await s.as(carer);

      const read = await plans.get(draft.id).orThrow();

      expect(read.problems[0]?.goals[0]?.status).toBe("in_progress");
      expect(read.evaluations).toHaveLength(1);
      expect(
        await plans
          .evaluate({ goalId: goal.id, input: { status: "achieved" } })
          .then(hint),
      ).toBe("CARE_PLAN_FORBIDDEN");

      await s.as(owner);

      const next = await plans
        .create({ ...subject, title: "Support plan", copyFromPlanId: draft.id })
        .orThrow();

      expect((await plans.publish(next.id).orThrow()).version).toBe(2);
      expect((await plans.get(draft.id).orThrow()).status).toBe("archived");
      expect(
        await plans
          .list({ subjectType: "client", subjectId: client?.id ?? "" })
          .orThrow(),
      ).toEqual([expect.objectContaining({ id: next.id, status: "active" })]);

      await s.service();
      await s.rows(
        "update better_supabase.care_plans set review_on = current_date - 1 where id = $1",
        [next.id],
      );
      expect(await plans.dueReviews().orThrow()).toBe(1);
      expect(await plans.dueReviews().orThrow()).toBe(0);

      await s.asRole(outsider);
      expect(await plans.get(next.id).then(hint)).toBe("CARE_PLAN_NOT_FOUND");

      await s.service();

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like 'care_plan%'",
      );

      expect(new Set(events.map((row) => row.type))).toEqual(
        new Set([
          "care_plan.created",
          "care_plan.published",
          "care_plan.archived",
          "care_plan.review_date_reached",
          "care_plan_action.started",
          "care_plan_action.ended",
          "care_plan_evaluation.created",
          "care_plan_goal.status_changed",
        ]),
      );
    } finally {
      await s.close();
    }
  });
});
