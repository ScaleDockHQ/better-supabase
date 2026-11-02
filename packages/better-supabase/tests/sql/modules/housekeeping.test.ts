import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const BLOCKS = ["rate-limit", "idempotency", "webhook-inbox", "chat-sdk-state"];

const CHECK = `do $$
declare
  v_run jsonb;
begin
  if (select count(*) from better_supabase.maintenance_jobs) <> 4 then
    raise exception 'jobs %', (select jsonb_agg(job) from better_supabase.maintenance_jobs);
  end if;
  if exists (select 1 from better_supabase.maintenance_jobs where not due) then
    raise exception 'a job that never ran is due';
  end if;

  insert into better_supabase.idempotency_keys (scope, key, request_hash, status, expires_at)
  values ('s', 'old', 'h', 'completed', now() - interval '1 hour'), ('s', 'new', 'h', 'completed', now() + interval '1 hour');

  v_run := better_supabase.maintenance();
  if jsonb_array_length(v_run) <> 4 or exists (select 1 from jsonb_array_elements(v_run) e where e ->> 'status' <> 'ok') then
    raise exception 'first run %', v_run;
  end if;
  if (select count(*) from better_supabase.idempotency_keys) <> 1 then
    raise exception 'the expired key survived';
  end if;
  if (select (result)::int from jsonb_to_recordset(v_run) as x(job text, result jsonb) where job = 'purge_idempotency_keys') <> 1 then
    raise exception 'purge result %', v_run;
  end if;

  if better_supabase.maintenance() <> '[]'::jsonb then
    raise exception 'jobs ran again before their interval';
  end if;
  if jsonb_array_length(better_supabase.maintenance('purge_webhooks')) <> 1 then
    raise exception 'a named job did not run';
  end if;
  if (select runs from better_supabase.maintenance_jobs where job = 'purge_webhooks') <> 2 then
    raise exception 'run count';
  end if;

  drop function better_supabase.purge_webhooks(interval, boolean, integer, text);
  v_run := better_supabase.maintenance(null, true);
  if jsonb_array_length(v_run) <> 4
    or (select count(*) from jsonb_array_elements(v_run) e where e ->> 'status' = 'error') <> 1
    or (select last_status from better_supabase.maintenance_jobs where job = 'purge_webhooks') <> 'error' then
    raise exception 'a failing job stopped the rest: %', v_run;
  end if;

  if better_supabase.maintenance_scheduler() <> 'none' or better_supabase.maintenance_schedule() <> 'none' then
    raise exception 'pg_cron is not installed here';
  end if;
end;
$$;`;

describe("housekeeping", () => {
  it("installs with every block that contributes a job", () => {
    const sql = renderBlocks(BLOCKS, {})
      .map((file) => file.contents)
      .join("\n");

    for (const job of [
      "purge_rate_limits",
      "purge_idempotency_keys",
      "purge_webhooks",
      "purge_chat_state",
    ]) {
      expect(sql).toContain(`'${job}'`);
    }
  });

  it(
    "runs due jobs once, records failures and reports the scheduler",
    { timeout: 60_000 },
    async () => {
      const files = renderBlocks(BLOCKS, {});

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          "create schema if not exists better_supabase;",
          ...files
            .filter((file) => file.kind !== "data")
            .map((file) => file.contents),
        ],
        seed: [CHECK],
      });

      expect(stack.url).not.toBe("");
    },
  );
});
