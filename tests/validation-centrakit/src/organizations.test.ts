import { EventHub } from "better-supabase";
import { createOrgs, sqlTransport } from "better-supabase/orgs";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  dbUrl,
  email,
  reachable,
  ROLES,
  USERS,
  withCentraKit,
} from "./stack.ts";

const live = await reachable();

describe.skipIf(!live)("organizations on CentraKit's tables", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("creates, invites, checks permissions and transfers ownership", async () => {
    await withCentraKit(pool, async (s) => {
      const events = new EventHub();
      const seen: string[] = [];
      events.on("kit", (event) => seen.push(event.type));
      const orgs = createOrgs({ transport: sqlTransport(s.sql), events });
      const roleOf = (org: string, user: string) =>
        s.value<string | null>(
          "(select role_id::text from centrakit.organization_users where organization_id = $1 and user_id = $2)",
          [org, user],
        );

      await s.as("service");
      for (const user of Object.values(USERS))
        await s.value("better_supabase.sync_profile($1)", [user]);
      expect(
        await s.rows(
          "select display_name from centrakit.contact_profiles where user_id = $1",
          [USERS.owner],
        ),
      ).toEqual([{ display_name: "owner Tester" }]);

      await s.as("owner");
      const { id: org } = await orgs
        .create({
          name: "Acme",
          slug: `acme-${USERS.owner.slice(0, 8)}`,
          website: "https://acme.test",
          default_currency: "USD",
        })
        .orThrow();
      expect(await roleOf(org, USERS.owner)).toBe(ROLES.owner);
      expect(
        await s.rows(
          "select website, default_currency from centrakit.organizations where id = $1",
          [org],
        ),
      ).toEqual([{ website: "https://acme.test", default_currency: "USD" }]);
      expect(
        await s.value(
          "(select count(*)::int from centrakit.workflow_runs where organization_id = $1)",
          [org],
        ),
      ).toBe(1);
      expect(
        await s.rows(
          "select kind, source from centrakit.workflow_events where organization_id = $1",
          [org],
        ),
      ).toEqual([{ kind: "org.created", source: "domain" }]);
      expect(
        (await orgs.create({ name: "App", slug: "app" })).error,
      ).toMatchObject({ hint: "ORG_SLUG_RESERVED" });

      const invite = async (who: "admin" | "member", role: string) =>
        orgs.invite({ organizationId: org, email: email(who), role }).orThrow();
      const adminInvite = await invite("admin", "admin");
      expect(
        await s.value(
          "(select role_id::text from centrakit.organization_invitations where token = $1)",
          [adminInvite.token],
        ),
      ).toBe(ROLES.admin);
      const memberInvite = await invite("member", ROLES.member);
      await s.as("admin");
      await orgs.acceptInvitation(adminInvite.token).orThrow();
      await s.as("member");
      await orgs.acceptInvitation(memberInvite.token).orThrow();
      expect(await roleOf(org, USERS.member)).toBe(ROLES.member);

      // The member's permissions come from the catalog, never from the role name.
      expect((await orgs.update(org, { name: "Mine" })).error).toMatchObject({
        hint: "ORG_FORBIDDEN",
      });
      expect(
        await s.value(
          "better_supabase.can('organization', $1, 'notifications.send')",
          [org],
        ),
      ).toBe(true);

      // A per-organization override takes a permission from the admin role.
      await s.as("admin");
      expect(
        await s.value(
          "better_supabase.can('organization', $1, 'organization.members.invite')",
          [org],
        ),
      ).toBe(true);
      await s.client.query(
        `insert into centrakit.organization_permission_overrides (organization_id, role_id, permission_id, granted)
         select $1, $2, id, false from centrakit.permissions where key = 'organization.members.invite'`,
        [org, ROLES.admin],
      );
      expect(
        await s.value(
          "better_supabase.can('organization', $1, 'organization.members.invite')",
          [org],
        ),
      ).toBe(false);
      expect(
        (
          await orgs.invite({
            organizationId: org,
            email: "late@centrakit.test",
            role: "member",
          })
        ).error,
      ).toMatchObject({ hint: "INVITATION_FORBIDDEN" });

      // The active organization lives in profiles.active_organization_id.
      await s.as("member");
      await orgs.switch(org).orThrow();
      expect(
        await s.value(
          "(select active_organization_id::text from centrakit.profiles where user_id = $1)",
          [USERS.member],
        ),
      ).toBe(org);
      expect(await s.value("better_supabase.current_tenant_id()::text")).toBe(
        org,
      );

      await s.as("owner");
      await orgs.transferOwnership(org, USERS.admin).orThrow();
      expect(await roleOf(org, USERS.admin)).toBe(ROLES.owner);
      expect(await roleOf(org, USERS.owner)).toBe(ROLES.admin);
      await s.client.query("set constraints all immediate");

      // Disabling the organization takes every permission away.
      await s.client.query(
        "update centrakit.organizations set disabled_at = now() where id = $1",
        [org],
      );
      await s.as("admin");
      expect(
        await s.value(
          "better_supabase.can('organization', $1, 'organization.settings.manage')",
          [org],
        ),
      ).toBe(false);

      expect(seen).toEqual(
        expect.arrayContaining([
          "org.created",
          "invitation.created",
          "org.member_added",
          "org.switched",
          "org.ownership_transferred",
        ]),
      );
    });
  });
});
