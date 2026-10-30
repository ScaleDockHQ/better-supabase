import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ADA = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const CLIENT = "44444444-4444-4444-8444-444444444444";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create schema if not exists realtime;
create or replace function realtime.send(payload jsonb, event text, topic text, private boolean default true)
returns void language plpgsql as $$ begin end $$;
`;

// The app's own clients and medication list: a renamed tenant and name column,
// and no form, strength or timestamps.
const APP = `
create table public.clients (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  name text not null
);

create table public.drugs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  label text not null,
  code_system text not null default 'custom',
  code text,
  unit text not null,
  high_risk boolean not null default false,
  archived_at timestamptz
);
`;

const BLOCKS: AnyBlocksConfig = {
  medications: {
    tables: { medications: "public.drugs" },
    options: { extraColumns: { ward: "text" } },
    columns: {
      medications: {
        tenant: "org_id",
        name: "label",
        form: null,
        strength: null,
        createdAt: null,
        updatedAt: null,
      },
    },
  },
};

const SUBJECTS = {
  client: { table: "public.clients", idType: "uuid", tenant: "org_id" },
} as const;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(
    [
      "memberships",
      "permissions",
      "subjects",
      "outbox",
      "notifications",
      "audit",
      "medications",
    ],
    {
      modules: BLOCKS,
      ownTables: { "public.drugs": "app.sql", "public.clients": "app.sql" },
      subjects: SUBJECTS,
    },
  );

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

/** Runs `statement` and returns the hint it raised, or `none`. */
const hintOf = (statement: string): string => `begin
    ${statement};
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;`;

describe("medications over the app's medication list", BOOT, () => {
  it("plans, records, marks missed, checks high-risk doses and caps as-needed doses", async () => {
    await expect(
      run(`do $$
declare
  v_paracetamol jsonb;
  v_warfarin jsonb;
  v_order jsonb;
  v_prn jsonb;
  v_dose jsonb;
  v_planned integer;
  v_missed uuid;
  v_hint text;
  v_chart jsonb;
begin
  ${SERVICE}
  insert into auth.users (id, email) values ('${ADA}', 'ada@example.com'), ('${BOB}', 'bob@example.com');
  insert into better_supabase.memberships (organization_id, user_id, role)
    values ('${TENANT}', '${ADA}', 'admin'), ('${TENANT}', '${BOB}', 'admin');
  insert into public.clients (id, org_id, name) values ('${CLIENT}', '${TENANT}', 'Client');

  v_paracetamol := better_supabase.save_medication('${TENANT}', 'Paracetamol', 'mg', 'atc', 'N02BE01');
  v_warfarin := better_supabase.import_medication('${TENANT}', '{"name":"Warfarin","unit":"mg","codeSystem":"atc","code":"B01AA03","highRisk":true}');
  if (select count(*) from public.drugs) <> 2 or (select label from public.drugs where code = 'N02BE01') <> 'Paracetamol' then
    raise exception 'medications %', v_paracetamol;
  end if;
  ${hintOf(`perform better_supabase.save_medication('${TENANT}', 'Again', 'mg', 'atc', 'N02BE01')`)}
  if v_hint <> 'MEDICATION_INVALID' then
    raise exception 'duplicate code: %', v_hint;
  end if;

  v_order := better_supabase.prescribe_medication('${TENANT}', 'client', '${CLIENT}', (v_warfarin ->> 'id')::uuid,
    jsonb_build_object('dose', 2, 'schedule', jsonb_build_object('everyHours', 1), 'startsOn', current_date, 'endsOn', current_date + 1, 'fields', jsonb_build_object('ward', 'B')));
  if v_order ->> 'status' <> 'active' or v_order ->> 'doseUnit' <> 'mg' or v_order -> 'fields' ->> 'ward' <> 'B' then
    raise exception 'order %', v_order;
  end if;
  ${hintOf(`perform better_supabase.prescribe_medication('${TENANT}', 'client', '${CLIENT}', (v_paracetamol ->> 'id')::uuid, '{"dose":500}')`)}
  if v_hint <> 'MEDICATION_ORDER_INVALID' then
    raise exception 'an order without a schedule: %', v_hint;
  end if;

  v_planned := better_supabase.plan_medication_administrations('${TENANT}', now() + interval '2 days');
  if v_planned < 1 or v_planned <> (select count(*) from better_supabase.medication_administrations where status = 'planned') then
    raise exception 'planned %', v_planned;
  end if;
  if better_supabase.plan_medication_administrations('${TENANT}', now() + interval '2 days') <> 0 then
    raise exception 'planning twice added doses';
  end if;

  select id into v_missed from better_supabase.medication_administrations order by scheduled_at limit 1;
  update better_supabase.medication_administrations set scheduled_at = now() - interval '2 hours' where id = v_missed;
  if better_supabase.mark_missed_medication_administrations() <> 1 then
    raise exception 'missed';
  end if;
  if (select count(*) from better_supabase.notification_recipients r join better_supabase.notification_events e on e.id = r.event_id where e.type = 'medication_administration.missed') <> 2 then
    raise exception 'missed notifications';
  end if;

  ${hintOf(`perform better_supabase.record_medication_administration(v_missed, 'given')`)}
  if v_hint <> 'MEDICATION_DOUBLE_CHECK_REQUIRED' then
    raise exception 'a high-risk dose without a check: %', v_hint;
  end if;
  v_dose := better_supabase.record_medication_administration(v_missed, 'given', null, null, '${BOB}');
  if v_dose ->> 'status' <> 'given' or (v_dose ->> 'dose')::numeric <> 2 or v_dose ->> 'checkedBy' <> '${BOB}' then
    raise exception 'given %', v_dose;
  end if;
  ${hintOf(`perform better_supabase.record_medication_administration(v_missed, 'refused', null, 'asleep')`)}
  if v_hint <> 'MEDICATION_ADMINISTRATION_INVALID' then
    raise exception 'recorded twice: %', v_hint;
  end if;

  v_prn := better_supabase.prescribe_medication('${TENANT}', 'client', '${CLIENT}', (v_paracetamol ->> 'id')::uuid,
    '{"dose":500,"asNeeded":true,"asNeededReason":"pain","maxPerDay":1000}');
  perform better_supabase.record_as_needed_administration((v_prn ->> 'id')::uuid, null, 'headache');
  perform better_supabase.record_as_needed_administration((v_prn ->> 'id')::uuid, null, 'headache');
  ${hintOf(`perform better_supabase.record_as_needed_administration((v_prn ->> 'id')::uuid, null, 'headache')`)}
  if v_hint <> 'MEDICATION_MAX_DOSE_EXCEEDED' then
    raise exception 'a third dose: %', v_hint;
  end if;

  v_prn := better_supabase.update_medication_order((v_prn ->> 'id')::uuid, '{"fields":{"ward":"C"}}');
  if v_prn -> 'fields' ->> 'ward' <> 'C' or v_prn ->> 'asNeededReason' <> 'pain' then
    raise exception 'updated fields %', v_prn;
  end if;
  ${hintOf(`perform better_supabase.update_medication_order((v_prn ->> 'id')::uuid, '{"fields":"C"}')`)}
  if v_hint <> 'MEDICATION_ORDER_INVALID' then
    raise exception 'fields that are not an object: %', v_hint;
  end if;

  v_chart := better_supabase.medication_chart('client', '${CLIENT}', now() - interval '1 day', now() + interval '2 days');
  if jsonb_array_length(v_chart -> 'orders') <> 2 or jsonb_array_length(v_chart -> 'administrations') <> v_planned + 2 then
    raise exception 'chart %', v_chart;
  end if;

  v_order := better_supabase.stop_medication_order((v_order ->> 'id')::uuid, 'INR too high');
  if v_order ->> 'status' <> 'stopped' or exists (select 1 from better_supabase.medication_administrations where status = 'planned') then
    raise exception 'stopped %', v_order;
  end if;
  if jsonb_array_length(better_supabase.medication_orders_of('client', '${CLIENT}')) <> 1 then
    raise exception 'orders of';
  end if;

  v_chart := better_supabase.import_medication_orders('${TENANT}', jsonb_build_array(
    jsonb_build_object('subjectType', 'client', 'subjectId', '${CLIENT}', 'externalId', 'rx-1', 'medicationId', v_paracetamol ->> 'id', 'dose', 500, 'asNeeded', true, 'fields', jsonb_build_object('ward', 'D')),
    jsonb_build_object('subjectType', 'client', 'subjectId', '${CLIENT}', 'externalId', 'rx-2', 'medication', jsonb_build_object('name', 'Ibuprofen', 'unit', 'mg', 'codeSystem', 'atc', 'code', 'M01AE01'), 'dose', 400, 'asNeeded', true)));
  if (v_chart ->> 'skipped')::int <> 0 or v_chart -> 'created' -> 0 -> 'fields' ->> 'ward' <> 'D' or v_chart -> 'created' -> 1 ->> 'source' <> 'import' then
    raise exception 'imported %', v_chart;
  end if;
  v_chart := better_supabase.import_medication_orders('${TENANT}', jsonb_build_array(
    jsonb_build_object('subjectType', 'client', 'subjectId', '${CLIENT}', 'externalId', 'rx-1', 'medicationId', v_paracetamol ->> 'id', 'dose', 500, 'asNeeded', true)));
  if (v_chart ->> 'skipped')::int <> 1 or jsonb_array_length(v_chart -> 'created') <> 0 then
    raise exception 'imported twice %', v_chart;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
