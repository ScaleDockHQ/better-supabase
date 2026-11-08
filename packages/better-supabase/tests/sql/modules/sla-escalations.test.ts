import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const TICKET = "44444444-4444-4444-8444-444444444444";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create table public.tickets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  status text not null default 'open',
  owner_id uuid
);
`;

const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}'), ('${BOB}');
`;

const LAYOUT = {
  subjects: {
    ticket: {
      table: "public.tickets",
      idType: "uuid",
      tenant: "organization_id",
    },
  },
  modules: {
    sla: {
      on: {
        ticket: { status: "status", owner: "owner_id", resolve: ["solved"] },
      },
    },
  },
} as const;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const BOOT = { timeout: 120_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(
    ["memberships", "permissions", "subjects", "sla"],
    LAYOUT,
  );

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
      ALLOW,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("sla escalation ladder", () => {
  it("renders the ladder into check_sla_clocks", () => {
    const sql = renderBlocks(
      ["memberships", "permissions", "subjects", "sla"],
      LAYOUT,
    )
      .filter((file) => file.module === "sla")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("create table");
    expect(sql).toContain("sla_escalations");
    expect(sql).toContain("SLA_ESCALATION_INVALID");
    expect(sql).toContain('jsonb_array_elements(y."escalations")');
  });
});

describe("sla escalations in Postgres", BOOT, () => {
  it("fires each step once, reassigns the owner and rejects bad ladders", async () => {
    await expect(
      run(`do $$
declare
  v_policy jsonb;
  v_count integer;
  v_owner uuid;
begin
  ${SERVICE}
  begin
    perform better_supabase.save_sla_policy('${TENANT}', null, '{"subjectType":"ticket","name":"Bad","resolutionMinutes":60,"escalations":[{"at":50,"action":"fly"}]}'::jsonb);
    raise exception 'a bad ladder was accepted';
  exception when others then
    if sqlerrm not like '%escalations%' then raise; end if;
  end;
  v_policy := better_supabase.save_sla_policy('${TENANT}', null, jsonb_build_object(
    'subjectType', 'ticket', 'name', 'Default', 'resolutionMinutes', 60,
    'escalations', jsonb_build_array(
      jsonb_build_object('at', 50, 'action', 'notify'),
      jsonb_build_object('at', 100, 'action', 'reassign', 'target', '${BOB}'),
      jsonb_build_object('at', 150, 'action', 'page'))));
  insert into public.tickets (id, organization_id, owner_id) values ('${TICKET}', '${TENANT}', '${ALICE}');
  update better_supabase.sla_clocks set started_at = now() - interval '2 hours', due_at = now() - interval '1 hour';
  v_count := better_supabase.check_sla_clocks();
  select owner_id into v_owner from public.tickets where id = '${TICKET}';
  if v_owner <> '${BOB}' then raise exception 'the owner was not reassigned'; end if;
  if (select count(*) from better_supabase.sla_escalations) <> 3 then
    raise exception 'expected three fired steps, got %', (select count(*) from better_supabase.sla_escalations);
  end if;
  if better_supabase.check_sla_clocks() <> 0 then raise exception 'steps fired twice'; end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
