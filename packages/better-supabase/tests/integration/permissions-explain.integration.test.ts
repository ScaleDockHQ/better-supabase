import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createPermissions } from "../../src/blocks/permissions/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("permissions.explain", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  const setup = async (layout: BlockSqlLayout = {}) => {
    const s = await BlockSession.open(pool);
    const owner = await s.user("owner");
    const admin = await s.user("admin");
    const member = await s.user("member");
    const outsider = await s.user("outsider");
    await s.install(["organizations", "permissions"], layout);
    const org = await s.organization(owner, { admin, member });
    const permissions = createPermissions({ transport: sqlTransport(s.sql) });

    return { s, owner, admin, member, outsider, org, permissions };
  };

  it("says why a member holds or lacks a key", async () => {
    const env = await setup();

    try {
      const { s, owner, member, outsider, org, permissions } = env;
      await s.as(owner);

      const held = await permissions
        .explain({ tenant: org, userId: member.id, key: "members.read" })
        .orThrow();

      expect(held.allowed).toBe(true);
      expect(held.reason).toBe("granted_by_role");
      expect(held.roles).toEqual(["member"]);
      expect(held.matchedBy.length).toBeGreaterThan(0);

      const lacking = await permissions
        .explain({ tenant: org, userId: member.id, key: "roles.manage" })
        .orThrow();

      expect(lacking.allowed).toBe(false);
      expect(lacking.reason).toBe("role_lacks_key");

      const stranger = await permissions
        .explain({ tenant: org, userId: outsider.id, key: "members.read" })
        .orThrow();

      expect(stranger.reason).toBe("not_a_member");
    } finally {
      await env.s.close();
    }
  });

  it("lets members explain themselves and refuses outsiders asking about others", async () => {
    const env = await setup();

    try {
      const { s, owner, member, outsider, org, permissions } = env;
      await s.as(member);

      expect(
        (
          await permissions
            .explain({ tenant: org, userId: member.id, key: "roles.manage" })
            .orThrow()
        ).allowed,
      ).toBe(false);

      await s.as(outsider);

      expect(
        hint(
          await permissions.explain({
            tenant: org,
            userId: owner.id,
            key: "roles.manage",
          }),
        ),
      ).toBe("PERMISSIONS_FORBIDDEN");
    } finally {
      await env.s.close();
    }
  });

  it("shows a forContext cap as not_in_scope", async () => {
    const env = await setup();

    try {
      const { s, owner, org, permissions } = env;
      await s.as(owner, { bsb_permission_cap: ["tasks.read"] });

      const capped = await permissions
        .explain({ tenant: org, userId: owner.id, key: "members.read" })
        .orThrow();

      expect(capped.allowed).toBe(false);
      expect(capped.reason).toBe("not_in_scope");
    } finally {
      await env.s.close();
    }
  });
});

describe.skipIf(!live)(
  "a role override can't grant more than the caller holds",
  () => {
    const pool = new Pool({ connectionString: dbUrl, max: 2 });

    afterAll(() => pool.end());

    it("refuses a key the caller lacks and a role above the caller", async () => {
      const s = await BlockSession.open(pool);

      try {
        const owner = await s.user("owner");
        const admin = await s.user("admin");
        await s.install(["organizations", "permissions"], {
          modules: { permissions: { model: "catalog" } },
        });
        const org = await s.organization(owner);
        await s.service();

        await s.client.query(
          `insert into better_supabase.memberships (organization_id, user_id, role)
         select $1, $2, r.id from better_supabase.roles r where r.key = 'admin'`,
          [org, admin.id],
        );

        const permissions = createPermissions({
          transport: sqlTransport(s.sql),
        });

        await s.as(owner);

        const ownerKeys = (
          await permissions.permissions({ tenant: org }).orThrow()
        ).keys;

        await s.as(admin);

        const adminKeys = (
          await permissions.permissions({ tenant: org }).orThrow()
        ).keys;

        const lacking = ownerKeys.find(
          (key) => !key.includes("*") && !adminKeys.includes(key),
        );

        expect(lacking).toBeDefined();

        const attempt = (role: string, permission: string) =>
          permissions.setOverride({
            tenant: org,
            role,
            permission,
            granted: true,
          });

        expect(hint(await attempt("owner", "members.read"))).toBe(
          "PERMISSIONS_ROLE_CEILING",
        );
        expect(hint(await attempt("member", lacking ?? ""))).toBe(
          "PERMISSIONS_KEY_CEILING",
        );
      } finally {
        await s.close();
      }
    });
  },
);
