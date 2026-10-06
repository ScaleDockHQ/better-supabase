import { EventHub } from "better-supabase";
import {
  createOrganizations,
  sqlTransport,
} from "better-supabase/blocks/organizations";
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
      events.on("block", (event) => seen.push(event.type));
      const organizations = createOrganizations({
        transport: sqlTransport(s.sql),
        events,
      });
      const roleOf = (organization: string, user: string) =>
        s.value<string | null>(
          "(select role_id::text from centrakit.organization_users where organization_id = $1 and user_id = $2)",
          [organization, user],
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
      const { id: organization } = await organizations
        .create({
          name: "Acme",
          slug: `acme-${USERS.owner.slice(0, 8)}`,
          website: "https://acme.test",
          default_currency: "USD",
        })
        .orThrow();
      expect(await roleOf(organization, USERS.owner)).toBe(ROLES.owner);
      expect(
        await s.rows(
          "select website, default_currency from centrakit.organizations where id = $1",
          [organization],
        ),
      ).toEqual([{ website: "https://acme.test", default_currency: "USD" }]);
      expect(
        await s.value(
          "(select count(*)::int from centrakit.workflow_runs where organization_id = $1)",
          [organization],
        ),
      ).toBe(1);
      expect(
        await s.rows(
          "select kind, source from centrakit.workflow_events where organization_id = $1",
          [organization],
        ),
      ).toEqual([{ kind: "organization.created", source: "domain" }]);
      expect(
        (await organizations.create({ name: "App", slug: "app" })).error,
      ).toMatchObject({ hint: "ORGANIZATION_SLUG_RESERVED" });

      const invite = async (who: "admin" | "member", role: string) =>
        organizations
          .invite({ organizationId: organization, email: email(who), role })
          .orThrow();
      const adminInvite = await invite("admin", "admin");
      expect(
        await s.value(
          "(select role_id::text from centrakit.organization_invitations where token = $1)",
          [adminInvite.token],
        ),
      ).toBe(ROLES.admin);
      const memberInvite = await invite("member", ROLES.member);
      await s.as("admin");
      await organizations.acceptInvitation(adminInvite.token).orThrow();
      await s.as("member");
      await organizations.acceptInvitation(memberInvite.token).orThrow();
      expect(await roleOf(organization, USERS.member)).toBe(ROLES.member);

      // The member's permissions come from the catalog, never from the role name.
      expect(
        (await organizations.update(organization, { name: "Mine" })).error,
      ).toMatchObject({
        hint: "ORGANIZATION_FORBIDDEN",
      });
      expect(
        await s.value(
          "better_supabase.can('organization', $1, 'notifications.send')",
          [organization],
        ),
      ).toBe(true);

      // A per-organization override takes a permission from the admin role.
      await s.as("admin");
      expect(
        await s.value(
          "better_supabase.can('organization', $1, 'organization.members.invite')",
          [organization],
        ),
      ).toBe(true);
      await s.client.query(
        `insert into centrakit.organization_permission_overrides (organization_id, role_id, permission_id, granted)
         select $1, $2, id, false from centrakit.permissions where key = 'organization.members.invite'`,
        [organization, ROLES.admin],
      );
      expect(
        await s.value(
          "better_supabase.can('organization', $1, 'organization.members.invite')",
          [organization],
        ),
      ).toBe(false);
      expect(
        (
          await organizations.invite({
            organizationId: organization,
            email: "late@centrakit.test",
            role: "member",
          })
        ).error,
      ).toMatchObject({ hint: "INVITATION_FORBIDDEN" });

      // The active organization lives in profiles.active_organization_id.
      await s.as("member");
      await organizations.switch(organization).orThrow();
      expect(
        await s.value(
          "(select active_organization_id::text from centrakit.profiles where user_id = $1)",
          [USERS.member],
        ),
      ).toBe(organization);
      expect(await s.value("better_supabase.current_tenant_id()::text")).toBe(
        organization,
      );

      await s.as("owner");
      await organizations
        .transferOwnership(organization, USERS.admin)
        .orThrow();
      expect(await roleOf(organization, USERS.admin)).toBe(ROLES.owner);
      expect(await roleOf(organization, USERS.owner)).toBe(ROLES.admin);
      await s.client.query("set constraints all immediate");

      // Disabling the organization takes every permission away.
      await s.client.query(
        "update centrakit.organizations set disabled_at = now() where id = $1",
        [organization],
      );
      await s.as("admin");
      expect(
        await s.value(
          "better_supabase.can('organization', $1, 'organization.settings.manage')",
          [organization],
        ),
      ).toBe(false);

      expect(seen).toEqual(
        expect.arrayContaining([
          "organization.created",
          "invitation.created",
          "organization.member_added",
          "organization.switched",
          "organization.ownership_transferred",
        ]),
      );
    });
  });
});
