import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
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

// The app's own jobs and schedules tables: renamed columns, no dedupe or
// attempt limit columns (the module adds them) and no schedule primary key.
const APP = `
create table public.jobs (
  job_id bigint generated always as identity primary key,
  lane text not null,
  body jsonb not null,
  attempts integer not null default 0,
  enqueued_at timestamptz not null default now(),
  run_at timestamptz not null default now(),
  done_at timestamptz,
  dead boolean not null default false
);

create table public.crons (
  name text not null,
  cron text not null,
  timezone text not null default 'UTC',
  lane text not null,
  payload jsonb not null default '{}',
  next_at timestamptz,
  last_at timestamptz,
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  tenant text,
  first_after timestamptz
);
`;

const BLOCKS: AnyBlocksConfig = {
  queue: {
    options: { backend: "table", scheduler: "drain" },
    tables: { messages: "public.jobs", schedules: "public.crons" },
    columns: {
      messages: {
        id: "job_id",
        queue: "lane",
        message: "body",
        visibleAt: "run_at",
        archivedAt: "done_at",
      },
      schedules: {
        jobName: "name",
        schedule: "cron",
        queue: "lane",
        nextRun: "next_at",
        lastRun: "last_at",
      },
    },
  },
};

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["queue"], {
    modules: BLOCKS,
    ownTables: { "public.jobs": "app.sql", "public.crons": "app.sql" },
  });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      APP,
      ...files
        .filter((file) => file.kind !== "data")
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

describe("queue over the app's tables", BOOT, () => {
  it("enqueues, deduplicates, claims and completes jobs", async () => {
    await expect(
      run(`do $$
declare
  v_id bigint;
  v_claim record;
begin
  v_id := better_supabase.enqueue_job('mail', '{"to":"a"}', 0, 3, 'k1');
  if better_supabase.enqueue_job('mail', '{"to":"a"}', 0, 3, 'k1') <> v_id then
    raise exception 'the dedupe key was not honoured';
  end if;
  if (select max_attempts || dedupe_key from public.jobs where job_id = v_id) <> '3k1' then
    raise exception 'jobs %', (select jsonb_agg(j) from public.jobs j);
  end if;
  select * into v_claim from better_supabase.claim_jobs('mail', 60, 10);
  if v_claim.id <> v_id or v_claim.attempts <> 1 then
    raise exception 'claim %', row_to_json(v_claim);
  end if;
  if better_supabase.complete_job('mail', v_id + 1, 1) then
    raise exception 'completed a job that does not exist';
  end if;
  if not better_supabase.complete_job('mail', v_id, 1) then
    raise exception 'complete failed';
  end if;
  if (select done_at from public.jobs where job_id = v_id) is null then
    raise exception 'the job was not archived';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("writes, keeps and advances drain schedules", async () => {
    await expect(
      run(`do $$
declare
  v_next timestamptz := date_trunc('milliseconds', now() - interval '1 minute');
  v_due record;
begin
  perform better_supabase.schedule_job('digest', '0 8 * * *', 'mail', '{}', 'UTC', v_next, 't1');
  perform better_supabase.schedule_job('digest', '0 8 * * *', 'mail', '{"v":2}', 'UTC', now() + interval '1 day', 't1');
  if (select count(*) from public.crons) <> 1
    or (select next_at from public.crons) <> v_next
    or (select payload from public.crons) <> '{"v":2}' then
    raise exception 'crons %', (select jsonb_agg(c) from public.crons c);
  end if;
  select * into v_due from better_supabase.claim_due_schedules();
  if v_due.job_name <> 'digest' then
    raise exception 'due %', row_to_json(v_due);
  end if;
  if not better_supabase.advance_schedule('digest', v_next, v_next + interval '1 day') then
    raise exception 'advance failed';
  end if;
  if (select last_at from public.crons) is distinct from v_next then
    raise exception 'last run %', (select last_at from public.crons);
  end if;
  if (select count(*) from better_supabase.list_schedules(null, 't1')) <> 1
    or better_supabase.unschedule_tenant('t1') <> 1 then
    raise exception 'tenant schedules';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
