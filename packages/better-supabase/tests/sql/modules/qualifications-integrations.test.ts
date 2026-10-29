import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ADA = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const COURSE = "44444444-4444-4444-8444-444444444444";

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
  "notifications",
  "teams",
  "employees",
  "contacts",
  "assets",
  "courses",
  "qualifications",
];

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 120_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(MODULES, {});

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

describe("qualifications with every integration installed", BOOT, () => {
  it("matches team and company requirements and grants from course certificates", async () => {
    await expect(
      run(`do $$
declare
  v_team jsonb;
  v_company jsonb;
  v_type jsonb;
  v_gaps jsonb;
  v_fk record;
begin
  ${SERVICE}
  insert into auth.users (id, email) values ('${ADA}', 'ada@example.com'), ('${BOB}', 'bob@example.com');
  insert into better_supabase.memberships (organization_id, user_id, role)
  values ('${TENANT}', '${ADA}', 'member'), ('${TENANT}', '${BOB}', 'member');
  v_team := better_supabase.create_team('${TENANT}', 'Warehouse', 'warehouse');
  perform better_supabase.add_team_member((v_team ->> 'id')::uuid, '${ADA}');

  v_type := better_supabase.save_qualification_type('${TENANT}', 'forklift', 'Forklift licence', array['member'], 12);
  perform better_supabase.add_qualification_requirement((v_type ->> 'id')::uuid, 'team', v_team ->> 'id');
  v_gaps := better_supabase.qualification_gaps('${TENANT}');
  if jsonb_array_length(v_gaps) <> 1 or v_gaps -> 0 ->> 'holderId' <> '${ADA}' then
    raise exception 'team gaps %', v_gaps;
  end if;
  v_gaps := better_supabase.qualification_gaps('${TENANT}', 'member', jsonb_build_object('teamId', v_team ->> 'id', 'holderId', '${BOB}'));
  if jsonb_array_length(v_gaps) <> 0 then
    raise exception 'filtered gaps %', v_gaps;
  end if;

  v_company := better_supabase.save_company('${TENANT}', null, '{"name": "Acme Haulage"}');
  perform better_supabase.save_qualification_type('${TENANT}', 'insurance', 'Liability insurance', array['company'], null, false);
  perform better_supabase.add_qualification_requirement(
    (select id from better_supabase.qualification_types where key = 'insurance'), 'holder', v_company ->> 'id');
  v_gaps := better_supabase.qualification_gaps('${TENANT}', 'company');
  if jsonb_array_length(v_gaps) <> 1 or v_gaps -> 0 ->> 'holderTitle' <> 'Acme Haulage' then
    raise exception 'company gaps %', v_gaps;
  end if;
  perform better_supabase.grant_qualification('${TENANT}', 'insurance', 'company', v_company ->> 'id', current_date);
  if jsonb_array_length(better_supabase.qualification_gaps('${TENANT}', 'company')) <> 0 then
    raise exception 'company still has gaps';
  end if;

  -- The certificate needs a finished enrollment; the foreign keys are dropped
  -- so the test can insert one directly.
  for v_fk in
    select conrelid::regclass as tbl, conname from pg_constraint
    where contype = 'f' and conrelid in ('better_supabase.course_certificates'::regclass, 'better_supabase.qualification_types'::regclass)
      and conname not like '%tenant%'
  loop
    execute format('alter table %s drop constraint %I', v_fk.tbl, v_fk.conname);
  end loop;
  update better_supabase.qualification_types set course_id = '${COURSE}' where key = 'forklift';
  insert into better_supabase.course_certificates (tenant_id, course_id, enrollment_id, user_id, code)
  values ('${TENANT}', '${COURSE}', gen_random_uuid(), '${ADA}', '0123456789abcdef0123456789abcdef');
  if better_supabase.qualified_holders('${TENANT}', 'forklift') <> jsonb_build_array('${ADA}') then
    raise exception 'course grant %', (select jsonb_agg(to_jsonb(q)) from better_supabase.qualifications q);
  end if;
  if (select source from better_supabase.qualifications where holder_id = '${ADA}') <> 'course' then
    raise exception 'source';
  end if;
  update better_supabase.course_certificates set revoked_at = now() where code = '0123456789abcdef0123456789abcdef';
  if better_supabase.qualified_holders('${TENANT}', 'forklift') <> '[]'::jsonb then
    raise exception 'course revoke';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
