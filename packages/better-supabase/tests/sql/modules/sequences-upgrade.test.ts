import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const SEQUENCE = "33333333-3333-4333-8333-333333333333";
const ACTIVE = "44444444-4444-4444-8444-444444444441";
const PAUSED = "44444444-4444-4444-8444-444444444442";
const EXITED = "44444444-4444-4444-8444-444444444443";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The version 1 tables, as 0.46 created them without mail-sync.
const VERSION_1 = `
create table better_supabase.sequences (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  key text not null,
  name text not null,
  description text,
  status text not null default 'draft',
  exit_on_reply boolean not null default true,
  mail_account_id uuid,
  steps jsonb not null default '[]',
  version integer not null default 1,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table better_supabase.sequence_enrollments (
  enrollment_id uuid primary key references better_supabase.enrollments (id) on delete cascade,
  tenant_id uuid not null,
  sequence_id uuid not null references better_supabase.sequences (id) on delete cascade,
  subject_type text not null,
  subject_id text not null,
  address text,
  name text,
  mail_account_id uuid,
  mail_thread_id uuid,
  step text,
  next_run_at timestamptz,
  status text not null default 'active',
  exit_reason text,
  attempts integer not null default 0,
  last_error text,
  variables jsonb not null default '{}',
  enrolled_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
`;

const enrollment = (id: string, subject: string, status: string): string =>
  `insert into better_supabase.enrollments (id, tenant_id, program, subject_type, subject_id, steps, completed_steps, status${status === "cancelled" ? ", cancelled_at" : ""})
values ('${id}', '${TENANT}', 'sequence:${SEQUENCE}', 'contact', '${subject}', array['intro', 'follow-up'], 1, '${status}'${status === "cancelled" ? ", now()" : ""});
insert into better_supabase.enrollment_steps (enrollment_id, tenant_id, step, completed_at)
values ('${id}', '${TENANT}', 'intro', now());`;

const SEED = `
insert into better_supabase.sequences (id, tenant_id, key, name, status, steps)
values ('${SEQUENCE}', '${TENANT}', 'welcome', 'Welcome', 'active',
  '[{"id": "intro", "kind": "wait", "minutes": 1}, {"id": "follow-up", "kind": "wait", "minutes": 60}]');
${enrollment(ACTIVE, "c1", "active")}
${enrollment(PAUSED, "c2", "active")}
${enrollment(EXITED, "c3", "cancelled")}
insert into better_supabase.sequence_enrollments
  (enrollment_id, tenant_id, sequence_id, subject_type, subject_id, address, name, step, next_run_at, status, exit_reason, attempts, last_error, variables)
values
  ('${ACTIVE}', '${TENANT}', '${SEQUENCE}', 'contact', 'c1', 'ada@example.com', 'Ada', 'follow-up', '2030-01-01T00:00:00Z', 'active', null, 2, 'timeout', '{"first": "Ada"}'),
  ('${PAUSED}', '${TENANT}', '${SEQUENCE}', 'contact', 'c2', 'bo@example.com', null, 'follow-up', '2030-01-02T00:00:00Z', 'paused', null, 0, null, '{}'),
  ('${EXITED}', '${TENANT}', '${SEQUENCE}', 'contact', 'c3', null, null, null, null, 'exited', 'replied', 0, null, '{}');
`;

const CHECK = `
do $$
declare
  v_row better_supabase.enrollments;
begin
  if to_regclass('better_supabase.sequence_enrollments') is not null then
    raise exception 'sequence_enrollments still exists';
  end if;
  select * into v_row from better_supabase.enrollments where id = '${ACTIVE}';
  if v_row.sequence_id <> '${SEQUENCE}' or v_row.sequence_address <> 'ada@example.com' or v_row.sequence_name <> 'Ada'
    or v_row.sequence_attempts <> 2 or v_row.sequence_last_error <> 'timeout' or v_row.sequence_variables <> '{"first": "Ada"}'
    or v_row.paused_at is not null or v_row.status <> 'active' then
    raise exception 'active run %', to_jsonb(v_row);
  end if;
  if (select due_at from better_supabase.enrollment_steps
      where enrollment_id = '${ACTIVE}' and step = 'follow-up' and completed_at is null) <> '2030-01-01T00:00:00Z' then
    raise exception 'active run has no open step';
  end if;
  select * into v_row from better_supabase.enrollments where id = '${PAUSED}';
  if v_row.paused_at is null or v_row.status <> 'active' then
    raise exception 'paused run %', to_jsonb(v_row);
  end if;
  select * into v_row from better_supabase.enrollments where id = '${EXITED}';
  if v_row.cancel_reason <> 'replied' or v_row.status <> 'cancelled' or v_row.sequence_id <> '${SEQUENCE}' then
    raise exception 'exited run %', to_jsonb(v_row);
  end if;
  if exists (select 1 from better_supabase.enrollment_steps where enrollment_id = '${EXITED}' and completed_at is null) then
    raise exception 'exited run has an open step';
  end if;
end;
$$;
`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

describe("sequences version 2 upgrade", BOOT, () => {
  it("moves sequence_enrollments rows onto their enrollments", async () => {
    const files = renderBlocks(["memberships", "permissions", "enrollments"]);

    const [plan] = upgradePlan([{ module: "sequences", version: 1 }], {
      modules: { enrollments: {}, sequences: {} },
    });

    expect(plan?.to).toBe(2);

    await using stack = await liteStack({
      driver: "pglite",
      migrations: [
        ROLES,
        ...files
          .filter((file) => file.kind !== "data")
          .map((file) => file.contents),
        VERSION_1,
      ],
      seed: [
        ...files
          .filter((file) => file.kind === "data")
          .map((file) => file.contents),
        SEED,
        ...(plan?.steps ?? []).map((step) => step.sql),
        CHECK,
      ],
    });

    expect(stack.url).not.toBe("");
  });
});
