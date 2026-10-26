import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const ADA = "22222222-2222-4222-8222-222222222222";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;

-- PGlite loads no pgcrypto here; the modules need random bytes and sha256.
create schema if not exists extensions;
create function extensions.gen_random_bytes(n integer) returns bytea
language sql volatile as $$ select decode(md5(random()::text), 'hex') $$;
create function extensions.digest(data text, type text) returns bytea
language sql immutable as $$ select sha256(convert_to(data, 'UTF8')) $$;

-- The notification broadcast trigger calls Realtime, which PGlite lacks.
create schema if not exists realtime;
create function realtime.send(payload jsonb, event text, topic text, private boolean default true)
returns void language sql as $$ select $$;
`;

const MODULES: AnyBlocksConfig = {
  notifications: {
    options: { channels: ["in_app", "push"], channelDefaults: { push: true } },
  },
};

const SEED = `
insert into auth.users (id, email) values ('${ADA}', 'ada@example.com');
update better_supabase.profiles set locale = 'nl-NL' where id = '${ADA}';
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["profiles", "notifications", "push"], {
    modules: MODULES,
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
      SEED,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

const NOTIFY = (extra: string): string =>
  `better_supabase.send_notification(jsonb_build_object('type', 'task.assigned', 'recipients', jsonb_build_array('${ADA}')${extra}))`;

describe("notification actions, resolution and locale", BOOT, () => {
  it("stores valid actions and rejects malformed ones", async () => {
    await expect(
      run(`do $$
declare
  v_hint text;
begin
  ${SERVICE}
  perform ${NOTIFY(`, 'actions', '[{"key":"approve","label":"Approve","operation":"approvals.decide","payload":{"decision":"approve"}}]'::jsonb`)};
  if (select actions -> 0 ->> 'key' from better_supabase.notification_events) <> 'approve' then
    raise exception 'actions were not stored';
  end if;
  begin
    perform ${NOTIFY(`, 'actions', '[{"key":"a b","label":"x"}]'::jsonb`)};
    raise exception 'a bad key was accepted';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'NOTIFICATION_ACTIONS_INVALID' then
      raise exception 'hint %', v_hint;
    end if;
  end;
  begin
    perform ${NOTIFY(`, 'actions', '[{"key":"a","label":"x"},{"key":"a","label":"y"}]'::jsonb`)};
    raise exception 'duplicate keys were accepted';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'NOTIFICATION_ACTIONS_INVALID' then
      raise exception 'hint %', v_hint;
    end if;
  end;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("records a resolution and claims deliveries in the recipient's locale", async () => {
    await expect(
      run(`do $$
declare
  v_claimed jsonb;
begin
  ${SERVICE}
  perform ${NOTIFY(`, 'subject_type', 'task', 'subject_id', 't1'`)};
  perform better_supabase.resolve_notifications('task.assigned', 'task', 't1', null, '{"decision":"approved"}'::jsonb);
  if (select resolution ->> 'decision' from better_supabase.notification_recipients) <> 'approved' then
    raise exception 'resolution was not stored';
  end if;
  v_claimed := better_supabase.claim_notification_deliveries('push');
  if v_claimed -> 0 ->> 'locale' is distinct from 'nl-NL' then
    raise exception 'claimed %', v_claimed;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});

describe("push tickets", BOOT, () => {
  it("stores tickets, lists unchecked ones and completes receipts", async () => {
    await expect(
      run(`do $$
declare
  v_delivery uuid;
  v_tickets jsonb;
  v_completed jsonb;
begin
  ${SERVICE}
  perform ${NOTIFY("")};
  select id into v_delivery from better_supabase.notification_deliveries where channel = 'push';
  if better_supabase.record_push_tickets(v_delivery,
    '[{"token":"a","id":"r1"},{"token":"b","error":"RequestFailed"}]') <> 2 then
    raise exception 'record_push_tickets count';
  end if;
  perform better_supabase.record_push_tickets(v_delivery, '[{"token":"b","id":"r2"},{"token":"a","error":"RequestFailed"}]');
  v_tickets := better_supabase.push_tickets_for(v_delivery);
  if v_tickets <> '[{"token":"a","id":"r1"},{"token":"b","id":"r2"}]'::jsonb then
    raise exception 'tickets %', v_tickets;
  end if;
  perform better_supabase.complete_notification_delivery(v_delivery, 'sent', 'expo', 'r1');
  if jsonb_array_length(better_supabase.unchecked_push_tickets(1000, '0 seconds')) <> 2 then
    raise exception 'unchecked %', better_supabase.unchecked_push_tickets(1000, '0 seconds');
  end if;
  if jsonb_array_length(better_supabase.unchecked_push_tickets(1000, '1 hour')) <> 0 then
    raise exception 'fresh tickets were returned';
  end if;
  v_completed := better_supabase.complete_push_receipts('[{"id":"r1","status":"ok"},{"id":"r2","status":"error","error":"DeviceNotRegistered"}]');
  if (v_completed ->> 'updated')::integer <> 2
    or (select string_agg(e ->> 'kind' || ':' || (e ->> 'provider_event_id'), ',' order by e ->> 'kind') from jsonb_array_elements(v_completed -> 'events') e)
      <> 'bounced:expo-receipt:r2,delivered:expo-receipt:r1' then
    raise exception 'completed %', v_completed;
  end if;
  if jsonb_array_length(better_supabase.unchecked_push_tickets(1000, '0 seconds')) <> 0 then
    raise exception 'receipts did not check the tickets';
  end if;
  if (select string_agg(kind, ',' order by kind) from better_supabase.notification_delivery_events) <> 'bounced,delivered' then
    raise exception 'events %', (select string_agg(kind, ',') from better_supabase.notification_delivery_events);
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses callers other than the service role", async () => {
    await expect(
      run(`do $$
declare
  v_hint text;
begin
  perform set_config('request.jwt.claims', '{"sub":"${ADA}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  begin
    perform better_supabase.unchecked_push_tickets();
    raise exception 'an authenticated user read tickets';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'PUSH_FORBIDDEN' then
      raise exception 'hint %', v_hint;
    end if;
  end;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
