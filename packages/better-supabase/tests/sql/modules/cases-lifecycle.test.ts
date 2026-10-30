import { describe, expect, it } from "vitest";

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

const MODULES = [
  "memberships",
  "permissions",
  "subjects",
  "pipelines",
  "numbering",
  "relations",
  "tasks",
  "cases",
];

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(
  check: string,
  modules: readonly string[] = MODULES,
): Promise<void> {
  const files = renderBlocks(modules, {});

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

const expectHint = (call: string, hint: string): string => `
  begin
    ${call};
    raise exception 'expected ${hint}';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from '${hint}' then
      raise exception 'expected ${hint}, got % (%)', v_hint, sqlerrm;
    end if;
  end;`;

const LIFECYCLE = `do $$
declare
  v_case better_supabase.cases;
  v_json jsonb;
  v_task uuid;
  v_hint text;
begin
  ${SERVICE}
  v_json := better_supabase.list_case_kinds('${TENANT}', false);
  if jsonb_array_length(v_json) <> 8 then
    raise exception 'kinds %', v_json;
  end if;
  v_json := better_supabase.open_case('${TENANT}', 'nonconformity', 'Scratched housing', null, 'high', 'internal', null, null, null, null);
  if v_json ->> 'number' not like 'NC-%' or v_json ->> 'status' <> 'open' or v_json ->> 'stageId' is null then
    raise exception 'opened %', v_json;
  end if;
  select * into v_case from better_supabase.cases where id = (v_json ->> 'id')::uuid;
  if better_supabase.case_close_blockers(v_case.id) <> array['CASE_ROOT_CAUSE_REQUIRED', 'CASE_ACTIONS_REQUIRED'] then
    raise exception 'blockers %', better_supabase.case_close_blockers(v_case.id);
  end if;
  ${expectHint("perform better_supabase.close_case(v_case.id, null)", "CASE_ROOT_CAUSE_REQUIRED")}
  perform better_supabase.record_case_root_cause(v_case.id, 'Worn fixture', null);
  v_json := better_supabase.create_case_action(v_case.id, 'corrective', 'Replace the fixture', null, null, true);
  v_task := (v_json ->> 'taskId')::uuid;
  ${expectHint("perform better_supabase.close_case(v_case.id, null)", "CASE_ACTIONS_OPEN")}
  update better_supabase.work_items set state = 'completed' where id = v_task;
  v_json := better_supabase.close_case(v_case.id, 'Fixed');
  if v_json ->> 'status' <> 'closed' or v_json ->> 'closedAt' is null or v_json ->> 'closeNote' <> 'Fixed' then
    raise exception 'closed %', v_json;
  end if;
  ${expectHint("perform better_supabase.record_case_root_cause(v_case.id, 'Other', null)", "CASE_CLOSED")}
  v_json := better_supabase.reopen_case(v_case.id, 'Came back');
  if v_json ->> 'status' <> 'open' or v_json ->> 'closedAt' is not null then
    raise exception 'reopened %', v_json;
  end if;
  v_json := better_supabase.cancel_case(v_case.id, 'Duplicate');
  if v_json ->> 'status' <> 'canceled' then
    raise exception 'canceled %', v_json;
  end if;
  v_json := better_supabase.get_case(v_case.id);
  if jsonb_array_length(v_json -> 'actions') <> 1 or v_json -> 'kind' ->> 'key' <> 'nonconformity'
    or (v_json -> 'actions' -> 0 ->> 'done')::boolean is not true then
    raise exception 'get %', v_json;
  end if;
  perform better_supabase.open_case('${TENANT}', 'complaint', 'Late delivery', null, 'low', 'customer', null, null, null, null);
  v_json := better_supabase.list_cases('${TENANT}', '{"status": "open"}'::jsonb);
  if jsonb_array_length(v_json -> 'items') <> 1 or v_json -> 'items' -> 0 ->> 'number' not like 'CMP-%' then
    raise exception 'list %', v_json;
  end if;
  v_json := better_supabase.case_stats('${TENANT}', null, null, null, 'kind');
  if jsonb_array_length(v_json) <> 2 then
    raise exception 'stats %', v_json;
  end if;
end;
$$;`;

describe("cases lifecycle", BOOT, () => {
  it("opens, blocks, closes, reopens and cancels a case", async () => {
    await expect(run(LIFECYCLE)).resolves.toBeUndefined();
  });

  it("guards a drag to the closing stage like close_case", async () => {
    await expect(
      run(`do $$
declare
  v_case better_supabase.cases;
  v_closed uuid;
  v_hint text;
begin
  ${SERVICE}
  perform better_supabase.ensure_case_kinds('${TENANT}');
  v_case := better_supabase.open_case_as(
    (select id from better_supabase.case_kinds where key = 'nonconformity' and tenant_id = '${TENANT}'),
    '{"title": "Bent pin"}'::jsonb, null);
  select id into v_closed from better_supabase.pipeline_stages
  where pipeline_id = v_case.pipeline_id and outcome = 'success';
  ${expectHint(`perform better_supabase.update_case(v_case.id, jsonb_build_object('stageId', v_closed))`, "CASE_ROOT_CAUSE_REQUIRED")}
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("schedules and reports the effectiveness check once the actions are done", async () => {
    await expect(
      run(`do $$
declare
  v_kind jsonb;
  v_id uuid;
  v_task uuid;
  v_hint text;
begin
  ${SERVICE}
  v_kind := better_supabase.save_case_kind('${TENANT}', 'audit_nc', 'Audit nonconformity', 'ANC', null, null, 30, true, true, true, false, null);
  v_id := (better_supabase.open_case('${TENANT}', 'audit_nc', 'Missing record', null, null, 'internal', null, null, null, null) ->> 'id')::uuid;
  if (select number from better_supabase.cases where id = v_id) not like 'ANC-%' then
    raise exception 'number %', (select number from better_supabase.cases where id = v_id);
  end if;
  perform better_supabase.record_case_root_cause(v_id, 'No checklist', null);
  v_task := (better_supabase.create_case_action(v_id, 'corrective', 'Add a checklist', null, null, true) ->> 'taskId')::uuid;
  update better_supabase.work_items set state = 'completed' where id = v_task;
  -- Separate statements: one would read the row before the job updates it.
  if better_supabase.notify_due_case_effectiveness() <> 0 then
    raise exception 'reported early';
  end if;
  if (select effectiveness_due_on from better_supabase.cases where id = v_id) is distinct from current_date + 30 then
    raise exception 'scheduled %', (select effectiveness_due_on from better_supabase.cases where id = v_id);
  end if;
  ${expectHint("perform better_supabase.close_case(v_id, null)", "CASE_EFFECTIVENESS_REQUIRED")}
  update better_supabase.cases set effectiveness_due_on = current_date - 1 where id = v_id;
  if better_supabase.notify_due_case_effectiveness() <> 1 or better_supabase.notify_due_case_effectiveness() <> 0 then
    raise exception 'not reported once';
  end if;
  perform better_supabase.record_case_effectiveness(v_id, true, null, 'Checklist in use');
  if better_supabase.close_case(v_id, null) ->> 'status' <> 'closed' then
    raise exception 'not closed';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("closes a case without tasks once its root cause is recorded", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.open_case('${TENANT}', 'observation', 'Untidy desk', null, null, 'internal', null, null, null, null) ->> 'id')::uuid;
  perform better_supabase.record_case_root_cause(v_id, 'No cleaning rota', null);
  if better_supabase.close_case(v_id, null) ->> 'status' <> 'closed' then
    raise exception 'not closed';
  end if;
end;
$$;`,
        ["memberships", "permissions", "subjects", "pipelines", "cases"],
      ),
    ).resolves.toBeUndefined();
  });

  it("opens an incident for a missed medication dose", async () => {
    const files = renderBlocks([...MODULES, "medications"], {
      modules: { medications: { options: { missedCaseKind: "incident" } } },
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
        `do $$
declare
  v_medication uuid;
  v_order uuid;
  v_case better_supabase.cases;
begin
  ${SERVICE}
  insert into better_supabase.medications (tenant_id, name, unit) values ('${TENANT}', 'Warfarin', 'mg') returning id into v_medication;
  insert into better_supabase.medication_orders (tenant_id, subject_type, subject_id, medication_id, dose, dose_unit, starts_on, as_needed)
    values ('${TENANT}', 'client', 'c-1', v_medication, 2, 'mg', current_date, true) returning id into v_order;
  insert into better_supabase.medication_administrations (tenant_id, order_id, scheduled_at, status)
    values ('${TENANT}', v_order, now() - interval '2 hours', 'planned');
  if better_supabase.mark_missed_medication_administrations() <> 1 then
    raise exception 'missed';
  end if;
  select * into v_case from better_supabase.cases;
  if v_case.number not like 'INC-%' or v_case.title not like 'Missed dose: Warfarin at %' or v_case.occurred_at is null then
    raise exception 'case %', to_jsonb(v_case);
  end if;
end;
$$;`,
      ],
    });

    expect(stack.url).not.toBe("");
  });

  it("refuses an unknown severity", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.open_case('${TENANT}', 'incident', 'Spill', null, 'enormous', 'internal', null, null, null, null);
end;
$$;`),
    ).rejects.toThrow(/severity/);
  });
});
