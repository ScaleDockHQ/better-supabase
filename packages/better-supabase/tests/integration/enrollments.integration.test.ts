import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createEnrollments,
  sqlTransport,
} from "../../src/blocks/enrollments/index.ts";
import { defineChecklist } from "../../src/blocks/onboarding/index.ts";
import { upgradePlan } from "../../src/sql/upgrade.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("enrollments", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("enrolls subjects in a program and tracks their steps", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "outbox", "audit", "enrollments"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const tenant = await s.organization(owner, { member });

      await s.as(owner);

      const enrollments = createEnrollments({
        transport: sqlTransport(s.sql),
        tenant,
      });

      const program = await enrollments
        .saveProgram({
          key: "customer-setup",
          name: "Customer setup",
          subjectTypes: ["customer"],
          steps: [{ id: "kickoff", title: "Kickoff" }, { id: "import" }],
        })
        .orThrow();

      expect(program.version).toBe(1);

      const customer = { type: "customer", id: "c1" };

      const enrolled = await enrollments
        .enroll({ program: "customer-setup", subject: customer })
        .orThrow();

      expect(enrolled).toMatchObject({
        subject: customer,
        status: "active",
        programVersion: 1,
        totalSteps: 2,
      });

      expect(
        (
          await enrollments
            .complete({ enrollmentId: enrolled.id, step: "kickoff" })
            .orThrow()
        ).completedSteps,
      ).toBe(1);

      const completed = await enrollments
        .complete({ enrollmentId: enrolled.id, step: "import" })
        .orThrow();

      expect(completed.status).toBe("completed");
      expect(completed.progress.map((step) => step.step)).toEqual([
        "kickoff",
        "import",
      ]);

      const changed = await enrollments
        .saveProgram({
          id: program.id,
          version: 1,
          steps: [{ id: "kickoff" }, { id: "import" }, { id: "train" }],
        })
        .orThrow();

      expect(changed.version).toBe(2);
      expect(
        await s.hint("better_supabase.save_enrollment_program($1, $2)", [
          tenant,
          { id: program.id, version: 1, name: "Stale" },
        ]),
      ).toBe("ENROLLMENTS_PROGRAM_CONFLICT");

      const reenrolled = await enrollments
        .enroll({ program: "customer-setup", subject: customer })
        .orThrow();

      expect(reenrolled).toMatchObject({
        id: enrolled.id,
        status: "active",
        programVersion: 2,
        completedSteps: 2,
        totalSteps: 3,
      });

      await s.as(member);

      const asMember = createEnrollments({
        transport: sqlTransport(s.sql),
        tenant,
      });

      expect(
        await asMember.list({ program: "customer-setup" }).orThrow(),
      ).toHaveLength(1);
      expect(
        await s.hint("better_supabase.cancel_enrollment($1)", [enrolled.id]),
      ).toBe("ENROLLMENTS_FORBIDDEN");

      await s.as(owner);

      const cancelled = await enrollments.cancel(enrolled.id).orThrow();

      expect(cancelled.status).toBe("cancelled");
      expect(
        await s.hint("better_supabase.complete_enrollment_step($1, $2)", [
          enrolled.id,
          "train",
        ]),
      ).toBe("ENROLLMENTS_INVALID");
      expect(
        (
          await enrollments
            .enroll({ program: "customer-setup", subject: customer })
            .orThrow()
        ).status,
      ).toBe("active");

      await s.as(outsider);
      expect(
        await s.hint("better_supabase.enroll($1, $2, $3, $4)", [
          tenant,
          "customer-setup",
          "customer",
          "c2",
        ]),
      ).toBe("ENROLLMENTS_FORBIDDEN");

      await s.service();
      expect(
        await s.rows<{ type: string }>(
          `select type from better_supabase.outbox_events
           where type like 'enrollment%' order by type`,
        ),
      ).toEqual(
        expect.arrayContaining([
          { type: "enrollment.created" },
          { type: "enrollment.step_completed" },
          { type: "enrollment.completed" },
          { type: "enrollment.cancelled" },
        ]),
      );

      await s.as(owner);
      expect(await enrollments.deleteProgram(program.id).orThrow()).toBe(true);
    } finally {
      await s.close();
    }
  });

  it("upgrades version 1 onboarding progress onto enrollments", async () => {
    const s = await BlockSession.open(pool);

    try {
      const tenant = crypto.randomUUID();
      const user = await s.user("user");

      const team = defineChecklist({
        id: "team",
        scope: "organization",
        steps: [{ id: "invite" }, { id: "billing" }],
      });

      await s.client.query(
        `create schema onboarding_up;
create table onboarding_up.onboarding_progress (
  id uuid primary key default gen_random_uuid(),
  checklist text not null,
  step text not null,
  user_id uuid,
  organization_id uuid,
  completed_by uuid,
  completed_at timestamptz not null default now()
);
insert into onboarding_up.onboarding_progress (checklist, step, organization_id, completed_by)
values ('team', 'invite', $1, $2), ('team', 'billing', $1, null);
insert into onboarding_up.onboarding_progress (checklist, step, user_id)
values ('profile', 'avatar', $2);`
          .replaceAll("$1", `'${tenant}'`)
          .replaceAll("$2", `'${user.id}'`),
      );

      const [plan] = upgradePlan([{ module: "onboarding", version: 1 }], {
        modules: {
          onboarding: {
            schema: "onboarding_up",
            options: { checklists: [team] },
          },
          enrollments: { schema: "onboarding_up" },
        },
      });

      for (const step of plan!.steps) {
        await s.client.query(step.sql);
      }

      expect(
        await s.rows<{
          program: string;
          subject_type: string;
          status: string;
          completed_steps: number;
          steps: string[];
        }>(
          `select program, subject_type, status, completed_steps, steps
           from onboarding_up.enrollments order by program`,
        ),
      ).toEqual([
        {
          program: "onboarding:profile",
          subject_type: "user",
          status: "completed",
          completed_steps: 1,
          steps: ["avatar"],
        },
        {
          program: "onboarding:team",
          subject_type: "organization",
          status: "completed",
          completed_steps: 2,
          steps: ["invite", "billing"],
        },
      ]);
      expect(
        await s.value<string | null>(
          "to_regclass('onboarding_up.onboarding_progress')::text",
        ),
      ).toBeNull();
    } finally {
      await s.close();
    }
  });
});
