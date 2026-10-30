import { describe, expect, it } from "vitest";

import type {
  AnyBlocksConfig,
  SubjectsConfig,
} from "../../../src/config/index.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const OTHER = "55555555-5555-4555-8555-555555555555";
const ADA = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const PATIENT = "44444444-4444-4444-8444-444444444444";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create table public.patients (
  id uuid primary key,
  organization_id uuid not null,
  name text not null
);
grant select on public.patients to authenticated;
`;

// Reading a patient takes a place on its record team; Ada leads it.
const SUBJECTS: SubjectsConfig = {
  patient: {
    table: "public.patients",
    idType: "uuid",
    title: "name",
    team: { actions: ["read"] },
  },
};

// Forms needs pg_jsonschema, which PGlite lacks; the pgTAP suite maps
// submissions on the fixture stack.
const MODULES = ["notifications", "observations"];

const BLOCKS: AnyBlocksConfig = {
  // PGlite has no realtime schema to broadcast to.
  notifications: { options: { realtime: "none" } },
  observations: { options: { defaults: "vitals" } },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const as = (
  user: string,
) => `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const SETUP = `${SERVICE}
  insert into auth.users (id, email) values ('${ADA}', 'ada@example.com'), ('${BOB}', 'bob@example.com');
  insert into better_supabase.memberships (organization_id, user_id, role)
  values ('${TENANT}', '${ADA}', 'admin'), ('${TENANT}', '${BOB}', 'member');
  insert into public.patients (id, organization_id, name) values ('${PATIENT}', '${TENANT}', 'Pat');
  perform better_supabase.add_subject_member('patient', '${PATIENT}', '${ADA}', null, 'lead');`;

const refused = (call: string, hint: string): string => `begin
    perform ${call};
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint is distinct from '${hint}' then
    raise exception '${call.replaceAll("'", "''")}: expected ${hint}, got %', v_hint;
  end if;`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 120_000 };

async function run(
  check: string,
  modules: AnyBlocksConfig = BLOCKS,
): Promise<void> {
  const files = renderBlocks(MODULES, { subjects: SUBJECTS, modules });

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
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("observations with notifications", BOOT, () => {
  it("records, flags, alerts, amends and summarizes vital signs", async () => {
    await expect(
      run(`do $$
declare
  v_hint text;
  v_obs jsonb;
  v_bp jsonb;
  v_fixed jsonb;
  v_list jsonb;
  v_series jsonb;
  v_ingest jsonb;
begin
  ${SETUP}
  ${as(ADA)}
  if jsonb_array_length(better_supabase.list_observation_definitions('${TENANT}')) <> 9 then
    raise exception 'vitals %', better_supabase.list_observation_definitions('${TENANT}');
  end if;

  v_obs := better_supabase.record_observation('${TENANT}', 'patient', '${PATIENT}', 'heart_rate', '72', now() - interval '2 hours');
  if v_obs ->> 'flag' <> 'normal' or (v_obs ->> 'value')::numeric <> 72 or v_obs ->> 'unit' <> '/min' then
    raise exception 'heart rate %', v_obs;
  end if;
  -- A monitor posts the critical value; notify leaves out the caller, so a
  -- lead who records it gets no alert about their own reading.
  ${SERVICE}
  perform set_config('request.jwt.claim.sub', '', true);
  v_obs := better_supabase.record_observation('${TENANT}', 'patient', '${PATIENT}', 'heart_rate', '135', now() - interval '1 hour');
  ${as(ADA)}
  if v_obs ->> 'flag' <> 'critical_high' then
    raise exception 'critical %', v_obs;
  end if;
  if not exists (select 1 from better_supabase.notification_events e join better_supabase.notification_recipients r on r.event_id = e.id where e.type = 'observation.critical' and r.user_id = '${ADA}') then
    raise exception 'the lead got no critical alert';
  end if;

  v_bp := better_supabase.record_observation('${TENANT}', 'patient', '${PATIENT}', 'blood_pressure', '{"systolic": 150, "diastolic": 85}');
  if v_bp ->> 'flag' <> 'high' or (v_bp -> 'value' ->> 'systolic')::numeric <> 150 then
    raise exception 'blood pressure %', v_bp;
  end if;
  ${refused(`better_supabase.record_observation('${TENANT}', 'patient', '${PATIENT}', 'blood_pressure', '{"systolic": 150}')`, "OBSERVATION_VALUE_INVALID")}
  ${refused(`better_supabase.record_observation('${TENANT}', 'patient', '${PATIENT}', 'heart_rate', '"fast"')`, "OBSERVATION_VALUE_INVALID")}
  ${refused(`better_supabase.record_observation('${TENANT}', 'patient', '${PATIENT}', 'heart_rate', '900')`, "OBSERVATION_VALUE_INVALID")}
  ${refused(`better_supabase.record_observation('${TENANT}', 'patient', '${PATIENT}', 'heart_rate', '70', now() + interval '1 day')`, "OBSERVATION_INVALID")}
  ${refused(`better_supabase.record_observation('${TENANT}', 'patient', '${PATIENT}', 'mood', '"ok"')`, "OBSERVATION_DEFINITION_NOT_FOUND")}
  ${refused(`better_supabase.record_observation('${OTHER}', 'patient', '${PATIENT}', 'heart_rate', '70')`, "OBSERVATION_FORBIDDEN")}

  v_fixed := better_supabase.amend_observation((v_obs ->> 'id')::uuid, '{"value": 115}', 'wrong patient monitor');
  if v_fixed ->> 'flag' <> 'high' or v_fixed ->> 'replacesId' <> v_obs ->> 'id' then
    raise exception 'amendment %', v_fixed;
  end if;
  if (select status from better_supabase.observations where id = (v_obs ->> 'id')::uuid) <> 'amended' then
    raise exception 'the amended observation is still final';
  end if;
  perform better_supabase.mark_observation_error((v_bp ->> 'id')::uuid, 'cuff too small');
  perform better_supabase.mark_observation_error((v_bp ->> 'id')::uuid, 'again');
  if (select reason from better_supabase.observations where id = (v_bp ->> 'id')::uuid) <> 'cuff too small' then
    raise exception 'marking twice changed the reason';
  end if;

  v_list := better_supabase.list_observations('patient', '${PATIENT}');
  if jsonb_array_length(v_list) <> 2 then
    raise exception 'final list %', v_list;
  end if;
  if jsonb_array_length(better_supabase.list_observations('patient', '${PATIENT}', null, true)) <> 4 then
    raise exception 'full list';
  end if;
  v_series := better_supabase.observation_series('patient', '${PATIENT}', 'heart_rate');
  if jsonb_array_length(v_series) <> 2 or (v_series -> 1 ->> 'value')::numeric <> 115 then
    raise exception 'series %', v_series;
  end if;
  v_series := better_supabase.observation_series('patient', '${PATIENT}', 'heart_rate', null, null, 'day');
  if (v_series -> -1 ->> 'max')::numeric <> 115 then
    raise exception 'buckets %', v_series;
  end if;
  ${refused(`better_supabase.observation_series('patient', '${PATIENT}', 'heart_rate', null, null, 'year')`, "OBSERVATION_INVALID")}
  if (better_supabase.latest_observations('patient', '${PATIENT}') -> 'heart_rate' ->> 'value')::numeric <> 115 then
    raise exception 'latest %', better_supabase.latest_observations('patient', '${PATIENT}');
  end if;

  -- The superuser running this block skips RLS, so team reads run as authenticated.
  execute 'set local role authenticated';
  v_list := better_supabase.list_observations('patient', '${PATIENT}');
  execute 'reset role';
  if jsonb_array_length(v_list) = 0 then
    raise exception 'the lead read no observations';
  end if;
  ${as(BOB)}
  execute 'set local role authenticated';
  v_list := better_supabase.list_observations('patient', '${PATIENT}');
  execute 'reset role';
  if jsonb_array_length(v_list) <> 0 then
    raise exception 'a member off the record team read its observations';
  end if;
  ${refused(`better_supabase.save_observation_definition('${TENANT}', 'mews', '{"title": "MEWS", "valueType": "integer"}')`, "OBSERVATION_FORBIDDEN")}

  ${SERVICE}
  v_ingest := better_supabase.ingest_observations('${TENANT}', jsonb_build_array(
    jsonb_build_object('subjectType', 'patient', 'subjectId', '${PATIENT}', 'definitionKey', 'oxygen_saturation', 'value', 97, 'externalId', 'oximeter-1'),
    jsonb_build_object('subjectType', 'patient', 'subjectId', '${PATIENT}', 'definitionKey', 'oxygen_saturation', 'value', 96, 'externalId', 'oximeter-2')
  ));
  v_ingest := better_supabase.ingest_observations('${TENANT}', jsonb_build_array(
    jsonb_build_object('subjectType', 'patient', 'subjectId', '${PATIENT}', 'definitionKey', 'oxygen_saturation', 'value', 97, 'externalId', 'oximeter-1')
  ));
  if (v_ingest ->> 'inserted')::int <> 0 or (v_ingest ->> 'skipped')::int <> 1 then
    raise exception 'ingest %', v_ingest;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("partitions the observations table by month", async () => {
    await expect(
      run(
        `do $$
declare
  v_first jsonb;
begin
  ${SETUP}
  if (select relkind from pg_class where oid = 'better_supabase.observations'::regclass) <> 'p' then
    raise exception 'not partitioned';
  end if;
  v_first := better_supabase.ingest_observations('${TENANT}', jsonb_build_array(
    jsonb_build_object('subjectType', 'patient', 'subjectId', '${PATIENT}', 'definitionKey', 'body_weight', 'value', 70.25, 'externalId', 'scale-1')
  ));
  if (better_supabase.ingest_observations('${TENANT}', jsonb_build_array(
    jsonb_build_object('subjectType', 'patient', 'subjectId', '${PATIENT}', 'definitionKey', 'body_weight', 'value', 70.25, 'externalId', 'scale-1')
  )) ->> 'skipped')::int <> 1 then
    raise exception 'a partitioned ingest took a duplicate';
  end if;
end;
$$;`,
        {
          observations: { options: { defaults: "vitals", partitioned: true } },
        },
      ),
    ).resolves.toBeUndefined();
  });
});
