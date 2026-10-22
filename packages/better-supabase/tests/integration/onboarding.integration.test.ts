import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createOnboarding,
  defineChecklist,
  sqlTransport,
} from "../../src/blocks/onboarding/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const team = defineChecklist({
  id: "team",
  scope: "organization",
  steps: [
    { id: "invite", events: ["organization.member_added"] },
    { id: "billing" },
  ],
});

const profile = defineChecklist({
  id: "profile",
  scope: "user",
  steps: [{ id: "avatar" }, { id: "bio" }],
});

describe.skipIf(!live)("onboarding", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("tracks user and organization checklists, by hand and from outbox events", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "outbox", "onboarding"], {
        modules: { onboarding: { options: { checklists: [team, profile] } } },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const tenant = await s.organization(owner, { member });

      await s.as(member);
      const onboarding = createOnboarding({ transport: sqlTransport(s.sql) });
      expect(await onboarding.complete(profile, "avatar").orThrow()).toBe(true);
      expect(await onboarding.complete(profile, "avatar").orThrow()).toBe(
        false,
      );
      const progress = await onboarding.progress(profile).orThrow();
      expect(progress).toMatchObject({ completed: 1, total: 2 });
      expect(progress.next?.id).toBe("bio");
      expect(await onboarding.reset(profile, "bio").orThrow()).toBe(false);

      expect(await onboarding.progress(team, tenant).orThrow()).toMatchObject({
        completed: 0,
      });
      expect(
        await onboarding
          .complete(team, "billing", tenant)
          .then((r) => !r.ok && r.error.hint),
      ).toBe("ONBOARDING_FORBIDDEN");
      expect(
        await s.hint(
          "better_supabase.complete_onboarding_step('team', 'nope', $1)",
          [tenant],
        ),
      ).toBe("ONBOARDING_STEP_UNKNOWN");
      expect(await s.hint("better_supabase.onboarding_progress('team')")).toBe(
        "ONBOARDING_SCOPE",
      );
      expect(
        await s.hint("better_supabase.onboarding_progress('profile', $1)", [
          tenant,
        ]),
      ).toBe("ONBOARDING_SCOPE");

      await s.as(owner);
      expect(await onboarding.complete(team, "billing", tenant).orThrow()).toBe(
        true,
      );
      expect((await onboarding.progress(profile).orThrow()).completed).toBe(0);

      await s.service();
      await s.rows(
        `insert into better_supabase.outbox_events (type, organization_id, actor_id, payload)
         values ('organization.member_added', $1, $2, '{}'), ('organization.member_added', null, $2, '{}')`,
        [tenant, owner.id],
      );
      await s.as(member);
      expect(await onboarding.progress(team, tenant).orThrow()).toMatchObject({
        done: true,
      });

      await s.asRole(member);
      expect(
        await s.rows(
          "select step from better_supabase.enrollment_steps order by step",
        ),
      ).toEqual([{ step: "avatar" }, { step: "billing" }, { step: "invite" }]);
      await s.asRole(outsider);
      expect(
        await s.rows("select step from better_supabase.enrollment_steps"),
      ).toEqual([]);
      await s.as(outsider);
      expect(
        await onboarding
          .progress(team, tenant)
          .then((r) => !r.ok && r.error.hint),
      ).toBe("ONBOARDING_FORBIDDEN");
      await s.as("anon");
      expect(
        await s.hint(
          "better_supabase.complete_onboarding_step('profile', 'bio')",
        ),
      ).toBe("ONBOARDING_FORBIDDEN");
    } finally {
      await s.close();
    }
  });
});
