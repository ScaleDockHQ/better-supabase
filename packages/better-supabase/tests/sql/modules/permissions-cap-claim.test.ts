import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const ORG = "11111111-1111-4111-8111-111111111111";
const OWNER = "22222222-2222-4222-8222-222222222222";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const ROWS = `insert into auth.users (id) values ('${OWNER}');
insert into better_supabase.memberships (organization_id, user_id, role)
values ('${ORG}', '${OWNER}', 'owner');
`;

const as = (claims: Record<string, unknown>) =>
  `perform set_config('request.jwt.claims', '${JSON.stringify({ role: "authenticated", sub: OWNER, ...claims })}', true);
  perform set_config('request.jwt.claim.sub', '${OWNER}', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["memberships", "permissions"], {
    modules: { memberships: {}, permissions: {} },
  });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      ROWS,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

const expectCan = (
  claims: Record<string, unknown>,
  key: string,
  can: boolean,
) =>
  `do $$
begin
  ${as(claims)}
  if better_supabase.member_can('${OWNER}', '${ORG}', '${key}') is distinct from ${String(can)} then
    raise exception 'member_can(%) with % is not ${String(can)}', '${key}', current_setting('request.jwt.claims');
  end if;
end;
$$;`;

describe("the permission cap claim", BOOT, () => {
  it("narrows member_can under its 0.15 name", async () => {
    await expect(
      run(
        [
          expectCan({}, "members.invite", true),
          expectCan({ bsb_permission_cap: ["audit.read"] }, "audit.read", true),
          expectCan(
            { bsb_permission_cap: ["audit.read"] },
            "members.invite",
            false,
          ),
        ].join("\n"),
      ),
    ).resolves.toBeUndefined();
  });

  it("still narrows member_can when a token carries only the 0.14 name", async () => {
    await expect(
      run(
        [
          expectCan({ bs_permission_cap: ["audit.read"] }, "audit.read", true),
          expectCan(
            { bs_permission_cap: ["audit.read"] },
            "members.invite",
            false,
          ),
          expectCan(
            {
              bsb_permission_cap: ["members.invite"],
              bs_permission_cap: ["audit.read"],
            },
            "audit.read",
            false,
          ),
        ].join("\n"),
      ),
    ).resolves.toBeUndefined();
  });
});
