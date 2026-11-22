import { EventHub } from "better-supabase";
import {
  createOrganizations,
  sqlTransport,
} from "better-supabase/blocks/organizations";
import { templatePlaceholderProblems } from "better-supabase/sql";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { centrakitProvider } from "./provider.ts";
import { dbUrl, reachable, USERS, withCentraKit } from "./stack.ts";

const live = await reachable();

const NEW_FIELDS = [
  "isApprover",
  "approverFor",
  "managedUsers",
  "canIn",
] as const;

describe("the provider snapshot carries the 0.82 fields", () => {
  const provider = centrakitProvider();

  it("names each new field and requires its function", () => {
    for (const field of NEW_FIELDS) {
      const template = provider.functions[field];
      expect(template).toBeDefined();
      const name = /^([\w.]+)\(/.exec(template ?? "")?.[1];
      expect(provider.requires?.some((item) => item.function === name)).toBe(
        true,
      );
    }
  });

  it("uses only placeholders the field accepts", () => {
    for (const field of NEW_FIELDS) {
      expect(
        templatePlaceholderProblems(field, provider.functions[field] ?? ""),
      ).toEqual([]);
    }
  });
});

describe.skipIf(!live)(
  "the provider's new functions on the live schema",
  () => {
    const pool = new Pool({ connectionString: dbUrl, max: 2 });

    afterAll(() => pool.end());

    it("answers canIn, isApprover, approverFor and managedUsers", async () => {
      await withCentraKit(pool, async (s) => {
        await s.as("service");

        for (const user of Object.values(USERS)) {
          await s.value("better_supabase.sync_profile($1)", [user]);
        }

        await s.as("owner");

        const { id: organization } = await createOrganizations({
          transport: sqlTransport(s.sql),
          events: new EventHub(),
        })
          .create({
            attributes: {
              name: "Fields",
              slug: `fields-${USERS.owner.slice(0, 8)}`,
            },
          })
          .orThrow();

        expect(
          await s.value<boolean>(
            "centrakit.authz_can_in('members.invite', $1)",
            [organization],
          ),
        ).toBe(true);
        expect(
          await s.value<boolean>(
            "centrakit.authz_can_in('members.invite', gen_random_uuid())",
          ),
        ).toBe(false);
        expect(
          await s.value<boolean>(
            "centrakit.authz_is_approver('x', 'leave', $1, $2, null)",
            [organization, USERS.member],
          ),
        ).toBe(true);
        expect(
          await s.value<boolean>(
            "centrakit.authz_is_approver('x', 'leave', $1, $2, null)",
            [organization, USERS.owner],
          ),
        ).toBe(false);
        expect(
          await s.value<boolean>(
            "$1::uuid in (select centrakit.authz_approver_for(gen_random_uuid(), 'leave'))",
            [USERS.owner],
          ),
        ).toBe(true);
        expect(
          await s.value<number>(
            "(select count(*)::int from centrakit.authz_managed_users())",
          ),
        ).toBe(0);

        await s.as("member");

        expect(
          await s.value<boolean>(
            "centrakit.authz_can_in('members.invite', $1)",
            [organization],
          ),
        ).toBe(false);
      });
    });
  },
);
