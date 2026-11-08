import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import type { RuleVersionContent } from "../../../src/sql/modules/deadlines-values.ts";

import { evaluateVersion } from "../../../src/sql/modules/deadlines-evaluate.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";
import { liteStack } from "../../../src/testing/lite.ts";
import { GOLDEN } from "../../fixtures/deadlines.ts";

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

const BOOT = { timeout: 180_000 };

const literal = (value: unknown): string =>
  `'${JSON.stringify(value).replaceAll("'", "''")}'::jsonb`;

const fixture = (name: string): RuleVersionContent => {
  const found = GOLDEN.find((entry) => entry.name === name);

  if (found === undefined) {
    throw new Error(`no fixture ${name}`);
  }

  return found.content;
};

async function run(
  modules: readonly string[],
  seed: readonly string[],
  replaceDeadlines?: string,
): Promise<void> {
  const files = renderBlocks(modules, {});

  const schema = files
    .filter((file) => file.kind === "schema")
    .map((file) =>
      replaceDeadlines !== undefined && file.module === "deadlines"
        ? replaceDeadlines
        : file.contents,
    );

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [ROLES, ...schema],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      ALLOW,
      ...seed,
    ],
  });

  expect(stack.url).not.toBe("");
}

const AZ = fixture("az");
const TX = fixture("tx");

const EVENTS = {
  notice_of_completion_recording_date: null,
  full_payment_date: null,
  lien_recording_date: null,
};

const COMMERCIAL_SUB = {
  claimant_contract_tier: "first_tier_sub",
  claimant_capacity: "contractor",
  property_use: "commercial",
  project_sector: "private",
  contract_is_written: true,
  payment_bond_recorded: false,
  first_furnishing_date: "2026-09-01",
  last_furnishing_date: "2026-10-15",
  ...EVENTS,
};

const SUPPLIER_HOME = {
  ...COMMERCIAL_SUB,
  claimant_capacity: "material_supplier",
  property_use: "residential",
  owner_occupancy: "owner_occupied",
  dwelling_units: "1",
};

const TEXAS_SUB = {
  claimant_contract_tier: "first_tier_sub",
  claimant_capacity: "contractor",
  property_use: "commercial",
  project_sector: "private",
  original_contract_date: "2026-08-01",
  ...EVENTS,
};

/** `[group, period, result, dueOn]` of each result, as SQL rows compare. */
const expectedSummary = (
  content: RuleVersionContent,
  facts: Readonly<Record<string, unknown>>,
  asOf: string,
): string =>
  literal(
    evaluateVersion(content, facts, asOf).map((result) => [
      result.group,
      result.period,
      result.result,
      result.dueOn,
    ]),
  );

const rowSummary = (rows: string): string =>
  `(select jsonb_agg(jsonb_build_array(r -> 'groupKey', r -> 'period', r -> 'result', r -> 'dueOn') order by o) from jsonb_array_elements(${rows}) with ordinality x(r, o))`;

describe("deadlines in Postgres", BOOT, () => {
  it("saves, approves and freezes a version's content", async () => {
    await expect(
      run(
        ["memberships", "permissions", "approvals", "deadlines"],
        [
          `do $$
declare
  v_version jsonb;
begin
  ${SERVICE}
  v_version := better_supabase.save_rule_version('az', 'lien', ${literal(AZ)}, '2020-01-01', 'Arizona');
  if v_version ->> 'status' <> 'draft' or jsonb_array_length(v_version -> 'groups') <> 4 or v_version -> 'counting' ->> 'status' <> 'approved' then
    raise exception 'draft %', v_version;
  end if;
  if better_supabase.rule_version_at('az', 'lien', '2026-01-01') is not null then
    raise exception 'a draft applies';
  end if;
  begin
    perform better_supabase.approve_rule_version((v_version ->> 'id')::uuid);
    raise exception 'approved without a request';
  exception when sqlstate '55000' then null;
  end;
  begin
    perform better_supabase.save_rule_version('AZ', 'lien', ${literal(AZ)});
    raise exception 'upper case jurisdiction';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform better_supabase.save_rule_version('az', 'lien', '{"rules":[{"key":"x"}],"groups":[]}'::jsonb);
    raise exception 'invalid rules saved';
  exception when sqlstate '22023' then null;
  end;
  if not exists (select 1 from unnest(better_supabase.validate_deadline_rules(
    '{"groups":[{"key":"lien","citation":{"reference":"s"}}],"rules":[{"key":"lien","group":"lien","adjust":"next_business_day","deadline":{"first_of":[{"before":"recorded","n":1,"unit":"days"},{"from":"end","n":2,"unit":"days"}]},"citation":{"reference":"s"}}]}'::jsonb)) i(issue)
    where i.issue like '%adjust next_business_day never follows a before count') then
    raise exception 'next business day after a before count accepted';
  end if;
  begin
    perform better_supabase.evaluate_deadlines(
      '{"groups":[{"key":"lien","citation":{"reference":"s"}}],"rules":[{"key":"lien","group":"lien","deadline":{"from":"end","n":2000000000,"unit":"business_days"},"citation":{"reference":"s"}}]}'::jsonb,
      '{"end":"2026-01-02"}'::jsonb, '2026-01-02');
    raise exception 'unbounded business days counted';
  exception when sqlstate '22023' then null;
  end;
  insert into better_supabase.approval_requests (tenant_id, subject_type, subject_id, action, policy, status, requested_by)
  values ('${TENANT}', 'deadline_rule_version', v_version ->> 'id', 'approve', '{}'::jsonb, 'approved', '${ALICE}');
  v_version := better_supabase.approve_rule_version(
    (v_version ->> 'id')::uuid,
    (select id from better_supabase.approval_requests where subject_id = v_version ->> 'id'));
  if v_version ->> 'status' <> 'approved'
    or v_version ->> 'contentHash' <> better_supabase.version_content_hash(v_version -> 'rules', v_version -> 'groups', v_version -> 'counting', v_version -> 'meta') then
    raise exception 'approve %', v_version;
  end if;
  begin
    update better_supabase.deadline_rule_versions set groups = '[]' where id = (v_version ->> 'id')::uuid;
    raise exception 'frozen version changed';
  exception when sqlstate '23000' then null;
  end;
  if (better_supabase.rule_version_at('az', 'lien', '2026-01-01') -> 'meta' ->> 'statute_edition') is null then
    raise exception 'meta not kept';
  end if;
end;
$$;`,
        ],
      ),
    ).resolves.toBeUndefined();
  });

  it("computes, stores, cascades, recomputes and satisfies a subject's deadlines", async () => {
    const newer = {
      ...AZ,
      rules: AZ.rules.map((rule) =>
        rule.key === "preliminary_notice__private_all_claimants"
          ? {
              ...rule,
              deadline: {
                from: "first_furnishing_date",
                n: 30,
                unit: "days" as const,
              },
            }
          : rule,
      ),
    };

    const asOf = "2026-11-07";

    await expect(
      run(
        ["memberships", "permissions", "outbox", "deadlines"],
        [
          `do $$
declare
  v_version jsonb;
  v_rows jsonb;
  v_row jsonb;
  v_events integer;
  v_notice uuid;
begin
  ${SERVICE}
  v_version := better_supabase.save_rule_version('az', 'lien', ${literal(AZ)}, '2020-01-01');
  perform better_supabase.approve_rule_version((v_version ->> 'id')::uuid);
  v_version := better_supabase.save_rule_version('tx', 'lien', ${literal(TX)}, '2020-01-01');
  perform better_supabase.approve_rule_version((v_version ->> 'id')::uuid);

  v_rows := better_supabase.compute_deadlines('${TENANT}', 'job', 'j1', 'az', 'lien', ${literal(COMMERCIAL_SUB)}, '${asOf}');
  if ${rowSummary("v_rows")} is distinct from ${expectedSummary(AZ, COMMERCIAL_SUB, asOf)} then
    raise exception 'computed %', ${rowSummary("v_rows")};
  end if;
  if (v_rows -> 1 ->> 'ruleKey') <> 'notice_and_claim_of_lien__private_all_claimants'
    or v_rows -> 1 -> 'basis' -> 'anchor' ->> 'fact' <> 'last_furnishing_date'
    or v_rows -> 1 -> 'deadline' -> 'first_of' is null then
    raise exception 'lien row %', v_rows -> 1;
  end if;
  select count(*) into v_events from better_supabase.outbox_events where type = 'deadline.computed';
  if v_events <> 4 then raise exception 'events %', v_events; end if;
  v_rows := better_supabase.compute_deadlines('${TENANT}', 'job', 'j1', 'az', 'lien', ${literal(COMMERCIAL_SUB)}, '${asOf}');
  select count(*) into v_events from better_supabase.outbox_events where type = 'deadline.computed';
  if v_events <> 4 then raise exception 'an unchanged compute recorded events: %', v_events; end if;

  v_notice := (v_rows -> 0 ->> 'id')::uuid;
  v_row := better_supabase.satisfy_deadline(v_notice, 'served');
  if v_row ->> 'state' <> 'satisfied' then raise exception 'satisfy %', v_row; end if;

  v_version := better_supabase.save_rule_version('az', 'lien', ${literal(newer)}, '2020-01-02');
  perform better_supabase.approve_rule_version((v_version ->> 'id')::uuid);
  if better_supabase.recompute_deadlines('${TENANT}', 'job', 'j1', '{"full_payment_date":"2027-03-01"}') <> 3 then
    raise exception 'recompute changed other than the three pending rows';
  end if;
  v_rows := better_supabase.list_deadlines('${TENANT}', '{"subjectId":"j1","groupKey":"release_of_lien"}');
  if v_rows -> 0 ->> 'dueOn' <> '2027-03-22' or v_rows -> 0 ->> 'ruleVersion' <> '1' then
    raise exception 'release %', v_rows;
  end if;
  if (select due_on from better_supabase.deadlines where id = v_notice) <> '2026-09-21' then
    raise exception 'a satisfied deadline changed';
  end if;
  v_rows := better_supabase.compute_deadlines('${TENANT}', 'job', 'j1', 'az', 'lien', ${literal(COMMERCIAL_SUB)}, '${asOf}', 'notice_and_claim_of_lien');
  if jsonb_array_length(v_rows) <> 1 or v_rows -> 0 ->> 'ruleVersion' <> '2' then
    raise exception 'one group %', v_rows;
  end if;

  v_rows := better_supabase.compute_deadlines('${TENANT}', 'job', 'j2', 'az', 'lien', ${literal(SUPPLIER_HOME)}, '${asOf}');
  if ${rowSummary("v_rows")} is distinct from ${expectedSummary(newer, SUPPLIER_HOME, asOf)}
    or v_rows -> 2 -> 'exception' ->> 'note' <> 'falls with notice_and_claim_of_lien' then
    raise exception 'cascade %', v_rows;
  end if;

  v_rows := better_supabase.compute_deadlines('${TENANT}', 'job', 'j3', 'tx', 'lien', ${literal(TEXAS_SUB)}, '2026-11-03', 'notice_of_claim');
  if jsonb_array_length(v_rows) <> 1 or v_rows -> 0 ->> 'result' <> 'unknown' or v_rows -> 0 ->> 'period' is not null then
    raise exception 'no months yet %', v_rows;
  end if;
  v_rows := better_supabase.compute_deadlines('${TENANT}', 'job', 'j3', 'tx', 'lien', ${literal({ ...TEXAS_SUB, first_furnishing_date: "2026-10-01" })}, '2026-11-03', 'notice_of_claim');
  if ${rowSummary("v_rows")} is distinct from ${literal([
    ["notice_of_claim", "2026-10", "due", "2027-01-15"],
    ["notice_of_claim", "2026-11", "due", "2027-02-15"],
    ["notice_of_claim", "2026-12", "due", "2027-03-15"],
  ])} then
    raise exception 'months %', v_rows;
  end if;
  if exists (select 1 from better_supabase.deadlines where subject_id = 'j3' and period is null) then
    raise exception 'the period-less row stayed';
  end if;
  perform better_supabase.satisfy_deadline((v_rows -> 0 ->> 'id')::uuid, 'sent');
  v_rows := better_supabase.compute_deadlines('${TENANT}', 'job', 'j3', 'tx', 'lien', ${literal({ ...TEXAS_SUB, first_furnishing_date: "2026-11-01" })}, '2026-11-03', 'notice_of_claim');
  if (select count(*) from better_supabase.deadlines where subject_id = 'j3') <> 3
    or (select state from better_supabase.deadlines where subject_id = 'j3' and period = '2026-10') <> 'satisfied' then
    raise exception 'a satisfied month went or a stale month stayed: %', v_rows;
  end if;
  if jsonb_array_length(better_supabase.list_deadlines('${TENANT}', '{"subjectId":"j3","period":"2026-11","provisional":false}')) <> 1 then
    raise exception 'list by period';
  end if;
  begin
    perform better_supabase.compute_deadlines('${TENANT}', 'job', 'j3', 'tx', 'lien', '{}', '2026-11-03', 'nope');
    raise exception 'unknown group computed';
  exception when sqlstate 'P0002' then null;
  end;
  v_row := better_supabase.compute_deadline('${TENANT}', 'job', 'j4', 'az', 'lien', 'preliminary_notice', ${literal(COMMERCIAL_SUB)}, '${asOf}');
  if v_row ->> 'groupKey' <> 'preliminary_notice' or v_row ->> 'dueOn' <> '2026-10-01' then
    raise exception 'deprecated compute_deadline %', v_row;
  end if;
  if better_supabase.evaluate_deadline_rule('{"key":"n","anchor":"d","offset":{"amount":-3,"unit":"days"},"requires":["s"],"citation":{"reference":"r"}}', '{"d":"2026-01-10","s":"x"}')
    <> '{"status":"due","dueOn":"2026-01-07"}'::jsonb then
    raise exception 'deprecated evaluate_deadline_rule';
  end if;
end;
$$;`,
        ],
      ),
    ).resolves.toBeUndefined();
  });

  it("drops the pending rows of groups a newer version no longer has and keeps satisfied ones", async () => {
    const v1 = fixture("v1");

    const narrowed = {
      ...v1,
      rules: v1.rules.filter((rule) => rule.group === "file_notice"),
      groups: v1.groups.filter((group) => group.key === "file_notice"),
    };

    const facts = literal({ first_day: "2026-01-02", state: "ca" });

    await expect(
      run(
        ["memberships", "permissions", "deadlines"],
        [
          `do $$
declare
  v_version jsonb;
  v_rows jsonb;
begin
  ${SERVICE}
  v_version := better_supabase.save_rule_version('ca', 'lien', ${literal(v1)}, '2020-01-01');
  perform better_supabase.approve_rule_version((v_version ->> 'id')::uuid);
  v_rows := better_supabase.compute_deadlines('${TENANT}', 'job', 'j1', 'ca', 'lien', ${facts}, '2026-02-01');
  if jsonb_array_length(v_rows) <> 3 then raise exception 'first compute %', v_rows; end if;
  perform better_supabase.compute_deadlines('${TENANT}', 'job', 'j2', 'ca', 'lien', ${facts}, '2026-02-01');
  perform better_supabase.satisfy_deadline((select id from better_supabase.deadlines where subject_id = 'j1' and group_key = 'business'), 'filed');

  v_version := better_supabase.save_rule_version('ca', 'lien', ${literal(narrowed)}, '2026-01-15');
  perform better_supabase.approve_rule_version((v_version ->> 'id')::uuid);
  v_rows := better_supabase.compute_deadlines('${TENANT}', 'job', 'j1', 'ca', 'lien', ${facts}, '2026-02-01');
  if (select array_agg(r ->> 'groupKey' order by r ->> 'groupKey') from jsonb_array_elements(v_rows) r) <> array['file_notice'] then
    raise exception 'second compute %', v_rows;
  end if;
  if (select array_agg(group_key || ':' || state order by group_key) from better_supabase.deadlines where subject_id = 'j1')
    <> array['business:satisfied', 'file_notice:pending'] then
    raise exception 'stored %', (select array_agg(group_key || ':' || state order by group_key) from better_supabase.deadlines where subject_id = 'j1');
  end if;
  if (select count(*) from better_supabase.deadlines where subject_id = 'j2') <> 3 then
    raise exception 'another subject changed';
  end if;
end;
$$;`,
        ],
      ),
    ).resolves.toBeUndefined();
  });

  it("upgrades a version 1 database: converts approved versions, keeps their hash, freezes them again", async () => {
    const v1 = readFileSync(
      new URL("../../fixtures/deadlines-v1.sql", import.meta.url),
      "utf-8",
    );

    const [plan] = upgradePlan([{ module: "deadlines", version: 1 }]);

    const current = renderBlocks(
      ["memberships", "permissions", "deadlines"],
      {},
    )
      .filter((file) => file.module === "deadlines" && file.kind === "schema")
      .map((file) => file.contents)
      .join("\n");

    const v1Rules = [
      {
        key: "file_notice",
        anchor: "first_day",
        offset: { amount: 90, unit: "days" },
        adjust: "next_business_day",
        requires: ["state"],
        citation: { reference: "Section 1" },
      },
      {
        key: "business",
        anchor: "first_day",
        offset: { amount: 10, unit: "business_days" },
        citation: { reference: "Section 1" },
      },
      {
        key: "months",
        anchor: "first_day",
        offset: { amount: 1, unit: "months" },
        adjust: "previous_business_day",
        citation: { reference: "Section 1" },
      },
    ];

    const converted = fixture("v1");

    expect(plan?.to).toBe(2);

    await expect(
      run(
        ["memberships", "permissions", "deadlines"],
        [
          `do $$
declare
  v_version jsonb;
begin
  ${SERVICE}
  v_version := better_supabase.save_rule_version('ca', 'notice', ${literal(v1Rules)}, '2020-01-01');
  v_version := better_supabase.approve_rule_version((v_version ->> 'id')::uuid);
  perform better_supabase.compute_deadline('${TENANT}', 'case', 'c1', 'ca', 'notice', 'file_notice', '{"first_day":"2026-01-02","state":"ca"}');
  create table public.v1_hash (hash text);
  insert into public.v1_hash values (v_version ->> 'contentHash');
end;
$$;`,
          ...(plan?.steps.map((step) => step.sql) ?? []),
          current,
          `do $$
declare
  v_version jsonb;
  v_rows jsonb;
begin
  ${SERVICE}
  v_version := better_supabase.rule_version_at('ca', 'notice', '2026-01-01');
  if v_version -> 'rules' <> ${literal(converted.rules)} or v_version -> 'groups' <> ${literal(converted.groups)} then
    raise exception 'converted %', v_version;
  end if;
  if v_version -> 'meta' ->> 'previous_content_hash' <> (select hash from public.v1_hash)
    or v_version ->> 'contentHash' <> better_supabase.version_content_hash(v_version -> 'rules', v_version -> 'groups', v_version -> 'counting', v_version -> 'meta') then
    raise exception 'hash %', v_version;
  end if;
  begin
    update better_supabase.deadline_rule_versions set groups = '[]';
    raise exception 'the frozen trigger is off';
  exception when sqlstate '23000' then null;
  end;
  if (select group_key from better_supabase.deadlines where subject_id = 'c1') <> 'file_notice' then
    raise exception 'group key not backfilled';
  end if;
  v_rows := better_supabase.compute_deadlines('${TENANT}', 'case', 'c1', 'ca', 'notice', '{"first_day":"2026-01-02","state":"ca"}', '2026-01-03');
  if ${rowSummary("v_rows")} is distinct from ${expectedSummary(converted, { first_day: "2026-01-02", state: "ca" }, "2026-01-03")} then
    raise exception 'computed %', v_rows;
  end if;
end;
$$;`,
        ],
        v1,
      ),
    ).resolves.toBeUndefined();
  });
});
