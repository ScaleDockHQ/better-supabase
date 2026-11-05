import { describe, expect, it } from "vitest";

import type { DeadlineRule } from "../../../src/sql/modules/deadlines-values.ts";

import { evaluateDeadlineRule } from "../../../src/sql/modules/deadlines-values.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;

create schema if not exists extensions;
create function extensions.digest(data bytea, type text) returns bytea
language sql immutable as $$ select sha256(data) $$;
`;

const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}');
insert into better_supabase.memberships (organization_id, user_id, role) values ('${TENANT}', '${ALICE}', 'owner');
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const NAMES = ["memberships", "permissions", "approvals", "deadlines"];

const BOOT = { timeout: 120_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(NAMES, {});

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

const CITATION = { reference: "Section 1" };

const RULES: readonly DeadlineRule[] = [
  {
    key: "file_notice",
    anchor: "first_day",
    offset: { amount: 90, unit: "days" },
    adjust: "next_business_day",
    requires: ["state"],
    citation: CITATION,
  },
  {
    key: "business",
    anchor: "first_day",
    offset: { amount: 10, unit: "business_days" },
    citation: CITATION,
  },
  {
    key: "months",
    anchor: "first_day",
    offset: { amount: 1, unit: "months" },
    adjust: "previous_business_day",
    citation: CITATION,
  },
];

const FACT_SETS: readonly Record<string, unknown>[] = [
  { first_day: "2026-01-02", state: "ca" },
  { first_day: "2026-01-31", state: "ca" },
  { first_day: "2026-02-27" },
  { first_day: "2024-02-29", state: "tx" },
  { first_day: "not a date", state: "tx" },
  { state: "tx" },
];

const literal = (value: unknown): string =>
  `'${JSON.stringify(value).replaceAll("'", "''")}'::jsonb`;

describe("deadlines in Postgres", BOOT, () => {
  it("evaluates rules in SQL exactly as the TypeScript evaluator does", async () => {
    const checks = RULES.flatMap((rule) =>
      FACT_SETS.map((facts) => {
        const expected = evaluateDeadlineRule(rule, facts);

        return `if better_supabase.evaluate_deadline_rule(${literal(rule)}, ${literal(facts)}) is distinct from ${literal(expected)} then
    raise exception 'mismatch for % with %: %', ${literal(rule.key)}, ${literal(facts)}, better_supabase.evaluate_deadline_rule(${literal(rule)}, ${literal(facts)});
  end if;`;
      }),
    ).join("\n  ");

    await expect(
      run(`do $$
begin
  ${checks}
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("approves a version once, computes, recomputes and satisfies deadlines", async () => {
    const rules = literal([RULES[0]]);

    await expect(
      run(`do $$
declare
  v_version jsonb;
  v_deadline jsonb;
begin
  ${SERVICE}
  v_version := better_supabase.save_rule_version('ca', 'notice', ${rules}, '2020-01-01', 'Notice');
  if v_version ->> 'status' <> 'draft' then raise exception 'draft %', v_version; end if;
  if better_supabase.rule_version_at('ca', 'notice', '2026-01-01') is not null then
    raise exception 'a draft applies';
  end if;
  begin
    perform better_supabase.approve_rule_version((v_version ->> 'id')::uuid);
    raise exception 'approved without a request';
  exception when sqlstate '55000' then null;
  end;
  begin
    perform better_supabase.save_rule_version('CA', 'notice', ${rules});
    raise exception 'upper case jurisdiction';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform better_supabase.save_rule_version('ca', 'notice', '[{"key":"x"}]'::jsonb);
    raise exception 'invalid rules saved';
  exception when sqlstate '22023' then null;
  end;
  insert into better_supabase.approval_requests (tenant_id, subject_type, subject_id, action, policy, status, requested_by)
  values ('${TENANT}', 'deadline_rule_version', v_version ->> 'id', 'approve', '{}'::jsonb, 'approved', '${ALICE}');
  v_version := better_supabase.approve_rule_version(
    (v_version ->> 'id')::uuid,
    (select id from better_supabase.approval_requests where subject_id = v_version ->> 'id'));
  if v_version ->> 'status' <> 'approved' or length(v_version ->> 'contentHash') <> 64 then
    raise exception 'approve %', v_version;
  end if;
  begin
    update better_supabase.deadline_rule_versions set rules = '[]' where id = (v_version ->> 'id')::uuid;
    raise exception 'frozen version changed';
  exception when sqlstate '23000' then null;
  end;

  v_deadline := better_supabase.compute_deadline('${TENANT}', 'case', 'c1', 'ca', 'notice', 'file_notice', '{"first_day":"2026-01-02"}');
  if v_deadline ->> 'result' <> 'unknown' or v_deadline -> 'missing' <> '["state"]'::jsonb then
    raise exception 'unknown %', v_deadline;
  end if;
  if better_supabase.recompute_deadlines('${TENANT}', 'case', 'c1', '{"state":"ca"}') <> 1 then
    raise exception 'recompute';
  end if;
  v_deadline := (better_supabase.list_deadlines('${TENANT}', '{"subjectId":"c1"}') -> 0);
  if v_deadline ->> 'result' <> 'due' or v_deadline ->> 'dueOn' <> '2026-04-02' then
    raise exception 'due %', v_deadline;
  end if;
  v_deadline := better_supabase.satisfy_deadline((v_deadline ->> 'id')::uuid, 'filed');
  if v_deadline ->> 'state' <> 'satisfied' then raise exception 'satisfy %', v_deadline; end if;
  if better_supabase.recompute_deadlines('${TENANT}', 'case', 'c1', '{"first_day":"2030-01-01"}') <> 0 then
    raise exception 'a satisfied deadline changed';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
