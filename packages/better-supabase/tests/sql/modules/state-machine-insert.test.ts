import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const MODULES: AnyBlocksConfig = {
  "state-machine": {
    options: {
      machines: {
        quote: {
          table: "better_supabase.quotes",
          column: "status",
          tenant: "tenant_id",
          initial: "draft",
          transitions: { draft: ["sent"], sent: ["accepted"] },
        },
      },
    },
  },
};

const INSERT = (status: string, number: number): string =>
  `insert into better_supabase.quotes (tenant_id, number, identifier, title, currency, status)
  values ('${TENANT}', ${String(number)}, 'Q-${String(number)}', 'Quote', 'EUR', '${status}')`;

async function run(check: string): Promise<void> {
  const files = renderBlocks(["quotes", "state-machine"], { modules: MODULES });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      ...files
        .filter((file) => file.module !== "state-machine")
        .filter((file) => file.kind === "schema")
        .map((file) => file.contents),
      ...files
        .filter((file) => file.module === "state-machine")
        .filter((file) => file.kind === "schema")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      `grant usage on schema auth to authenticated;
grant execute on all functions in schema auth to authenticated;
grant usage on schema better_supabase to authenticated;
grant insert on better_supabase.quotes to authenticated;
alter table better_supabase.quotes disable row level security;
create function public.trusted_insert() returns void language plpgsql security definer set search_path = '' as $$
begin
  ${INSERT("accepted", 3)};
end;
$$;
grant execute on function public.trusted_insert() to authenticated;`,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("a state machine's insert check", { timeout: 60_000 }, () => {
  it("holds a client to the first statuses and lets trusted SQL through", async () => {
    await expect(
      run(`do $$
begin
  perform set_config('request.jwt.claims', '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}', true);
  perform set_config('role', 'authenticated', true);
  ${INSERT("sent", 1)};
  begin
    ${INSERT("accepted", 2)};
    raise exception 'a client inserted an accepted quote';
  exception when sqlstate '22023' then
    null;
  end;
  perform public.trusted_insert();
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
