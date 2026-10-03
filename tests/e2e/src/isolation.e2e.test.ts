import { expectTenantIsolation } from "better-supabase/testing";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { betterSupabase } from "@better-supabase/example-nextjs/supabase";

import {
  ACME,
  createUser,
  OTHER,
  reachable,
  stack,
  type TestUser,
} from "./stack.ts";

const live = await reachable();
const RUN = Date.now();

describe.skipIf(!live)("Next.js example tenant isolation", () => {
  const users = new Map<string, TestUser>();

  beforeAll(async () => {
    users.set(ACME, await createUser(ACME));
    users.set(OTHER, await createUser(OTHER));
  });

  afterAll(async () => {
    for (const user of users.values()) await user.remove();
  });

  it("keeps organizations apart on every command", async () => {
    const userOf = (tenant: { id: string }): string => users.get(tenant.id)!.id;
    const member = (id: string) => ({
      id,
      claims: { sub: userOf({ id }), app_metadata: { tenant_id: id } },
    });
    const report = await expectTenantIsolation(betterSupabase, {
      stack,
      tenants: [member(ACME), member(OTHER)],
      tables: {
        tags: {
          row: (tenant, n) => ({
            organizationId: tenant.id,
            name: `iso-${RUN}-${n}`,
          }),
          update: { color: "red" },
        },
        notifications: {
          row: (tenant, n) => ({
            organizationId: tenant.id,
            userId: userOf(tenant),
            title: `Isolation ${RUN} ${n}`,
          }),
          update: { title: "Changed" },
        },
      },
    });
    expect(report.checks.filter((check) => !check.ok)).toEqual([]);
    expect(report.checks).toHaveLength(20);
  });
});
