import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createPermissions } from "../../src/blocks/permissions/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("permission escalation", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("keeps an admin from granting keys it lacks or editing roles above its own", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const admin = await s.user("admin");
      await s.install(["organizations", "permissions"], {
        modules: { permissions: { model: "catalog" } },
      });
      const org = await s.organization(owner, { admin });
      const permissions = createPermissions({ transport: sqlTransport(s.sql) });
      await s.as(admin);

      // The owner role is above the admin's.
      expect(
        hint(
          await permissions.setOverride({
            tenant: org,
            role: "owner",
            permission: "members.read",
            granted: false,
          }),
        ),
      ).toBe("PERMISSIONS_ROLE_CEILING");

      // A key the admin does not hold can't be handed to a lower role.
      expect(
        hint(
          await permissions.setOverride({
            tenant: org,
            role: "member",
            permission: "organization.delete",
            granted: true,
          }),
        ),
      ).toBe("PERMISSIONS_KEY_CEILING");
    } finally {
      await s.close();
    }
  });
});
