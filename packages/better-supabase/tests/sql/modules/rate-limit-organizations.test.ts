import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["rate-limit"], {
    modules: { "rate-limit": { options: { preRequest: false } } },
  });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      ...files
        .filter((file) => file.kind === "schema")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("rate-limit organization rules", BOOT, () => {
  it("applies an organization's rule over the scope's global rule", async () => {
    await expect(
      run(`do $$
declare
  org uuid := gen_random_uuid();
begin
  perform better_supabase.set_rate_limit('ai', 5);
  perform better_supabase.set_organization_rate_limit('ai', org, 1, interval '1 hour');
  if (select count(*) from better_supabase.rate_limit_rules where scope = 'ai') <> 2 then
    raise exception 'expected a global and an organization rule';
  end if;
  if not (select h.allowed from better_supabase.hit_rate_limit('ai', 'u', null, null, org) h)
    or (select h.allowed from better_supabase.hit_rate_limit('ai', 'u', null, null, org) h) then
    raise exception 'the organization rule was not applied';
  end if;
  if not (select h.allowed from better_supabase.hit_rate_limit('ai', 'other') h)
    or not (select h.allowed from better_supabase.hit_rate_limit('ai', 'other') h) then
    raise exception 'the global rule was not applied';
  end if;
  if not (better_supabase.check_rate_limits(jsonb_build_array(
      jsonb_build_object('scope', 'ai', 'key', 'batch', 'tenant_id', org)
    )) ->> 'allowed')::boolean then
    raise exception 'check_rate_limits ignored the organization rule';
  end if;
  perform better_supabase.set_organization_rate_limit('ai', org, null);
  perform better_supabase.set_rate_limit('ai', null);
  if exists (select 1 from better_supabase.rate_limit_rules) then
    raise exception 'the rules were not removed';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});

describe("rate-limit upgrade", () => {
  it("adds tenant_id and drops the primary key from version 1", () => {
    const [plan] = upgradePlan([{ module: "rate-limit", version: 1 }]);
    const sql = plan?.steps.map((step) => step.sql).join("\n") ?? "";

    expect(sql).toContain("add column if not exists");
    expect(sql).toContain("tenant_id");
    expect(sql).toContain("drop constraint if exists");
    expect(sql).toContain("rate_limit_rules_pkey");
  });
});
