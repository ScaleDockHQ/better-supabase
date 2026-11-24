import { shareGuard } from "better-supabase/server";
import { inTenantFill } from "better-supabase/testing";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Session } from "./stack.ts";

import { contextDb, customerService } from "./services/customers.ts";
import { dbUrl, reachable, ROLES, USERS, withCentraKit } from "./stack.ts";

const live = await reachable();

const claimsOf = (user: string) => ({ sub: user, role: "authenticated" });

/** The context a `share: "tenant"` fill starts from, for the member. */
const memberCtx = (s: Session) => ({
  auth: { kind: "user" as const, claims: claimsOf(USERS.member) },
  db: contextDb(s.sql, claimsOf(USERS.member)),
});

async function acme(s: Session): Promise<string> {
  await s.as("service");

  const org = (
    await s.rows<{ id: string }>(
      "insert into centrakit.organizations (name, slug) values ('Acme', $1) returning id",
      [`acme-${crypto.randomUUID().slice(0, 8)}`],
    )
  )[0]!.id;

  await s.client.query(
    "insert into centrakit.organization_users (organization_id, user_id, role_id) values ($1, $2, $3)",
    [org, USERS.member, ROLES.member],
  );
  await s.client.query(
    "insert into centrakit.customers (organization_id, company_name) values ($1, 'Bakery Jansen'), ($1, 'Garage De Vries')",
    [org],
  );

  // The app's pool connection runs as the caller, so RLS decides the rows.
  await s.as("member");
  await s.client.query("set local role authenticated");

  return org;
}

describe.skipIf(!live)("an app's own service in a tenant fill", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("pages customers through the app's db under the table guard", async () => {
    await withCentraKit(pool, async (s) => {
      const org = await acme(s);

      const appDb = contextDb(s.sql, claimsOf(USERS.member));

      const fill = await inTenantFill(memberCtx(s), ["customers"], (ctx) =>
        customerService(shareGuard(ctx, appDb)).page(org),
      );

      expect(fill.refused).toBeUndefined();
      expect(
        fill.value.data?.items.map((row) => row.companyName).toSorted(),
      ).toEqual(["Bakery Jansen", "Garage De Vries"]);

      await s.client.query("reset role");
    });
  });

  it("refuses a table the entry doesn't list, so the fill isn't stored", async () => {
    await withCentraKit(pool, async (s) => {
      const org = await acme(s);

      const appDb = contextDb(s.sql, claimsOf(USERS.member));

      const fill = await inTenantFill(memberCtx(s), ["customers"], (ctx) =>
        customerService(shareGuard(ctx, appDb)).members(org),
      );

      const result = fill.value;

      expect(result.error?.code).toBe("SHARE_REFUSED");
      expect(fill.refused?.message).toContain("organizationUsers");

      await s.client.query("reset role");
    });
  });

  it("refuses a db that runs as another user or as the service role", async () => {
    await withCentraKit(pool, async (s) => {
      const org = await acme(s);

      for (const claims of [
        claimsOf(USERS.owner),
        { sub: USERS.member, role: "service_role" },
        {},
      ]) {
        const other = contextDb(s.sql, claims);

        const fill = await inTenantFill(memberCtx(s), ["customers"], (ctx) =>
          customerService(shareGuard(ctx, other)).page(org),
        );

        expect(fill.value.error?.code).toBe("SHARE_REFUSED");
        expect(fill.refused?.message).toContain("doesn't run as the caller");
      }

      await s.client.query("reset role");
    });
  });

  it("leaves the db unchanged outside a shared fill", async () => {
    await withCentraKit(pool, async (s) => {
      const org = await acme(s);

      const appDb = contextDb(s.sql, claimsOf(USERS.member));

      expect(shareGuard(memberCtx(s), appDb)).toBe(appDb);
      const members = await customerService(appDb).members(org);

      expect(members.data).toEqual([
        expect.objectContaining({ organizationId: org }),
      ]);

      await s.client.query("reset role");
    });
  });
});
