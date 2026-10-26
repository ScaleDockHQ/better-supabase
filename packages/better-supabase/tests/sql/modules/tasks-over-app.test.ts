import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { withBlockSubjects } from "../../../src/config/block-subjects.ts";
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

// The app's own ticket and initiative tables: renamed columns, enum states,
// and no body, project, iteration, estimate, progress, start, end, recurrence,
// creator, owner or date columns. The module adds the board columns it needs.
const APP = `
create type public.ticket_state as enum ('triage', 'backlog', 'unstarted', 'started', 'completed', 'canceled');
create type public.ticket_close as enum ('completed', 'not_planned', 'duplicate');
create type public.initiative_status as enum ('planned', 'active', 'paused', 'completed', 'canceled');

create table public.initiatives (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  code text not null,
  label text not null,
  status public.initiative_status not null default 'planned',
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.tickets (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  seq bigint,
  code text,
  title text not null,
  state public.ticket_state not null default 'backlog',
  close_reason public.ticket_close,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  notes text
);
`;

const OWN_TABLES = {
  "public.initiatives": "app.sql",
  "public.tickets": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  tasks: {
    tables: {
      items: "public.tickets",
      projects: "public.initiatives",
      iterations: null,
    },
    columns: {
      items: {
        tenant: "org_id",
        number: "seq",
        identifier: "code",
        body: null,
        project: null,
        iteration: null,
        estimate: null,
        progress: null,
        startAt: null,
        endAt: null,
        recursFrom: null,
        createdBy: null,
      },
      projects: {
        tenant: "org_id",
        key: "code",
        name: "label",
        owner: null,
        startOn: null,
        targetOn: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(
  check: string,
  modules: AnyBlocksConfig = BLOCKS,
  extra: readonly string[] = [],
): Promise<void> {
  const blocks = [
    "memberships",
    "permissions",
    "subjects",
    "pipelines",
    ...extra,
    "tasks",
  ];

  // The config resolver registers the block's subjects with the app's columns.
  const files = renderBlocks(blocks, {
    modules,
    ownTables: OWN_TABLES,
    subjects: withBlockSubjects({}, blocks, modules),
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

describe("tasks over the app's tables", BOOT, () => {
  it("creates, updates, closes and lists work items in enum state columns", async () => {
    await expect(
      run(`do $$
declare
  v_item jsonb;
  v_id uuid;
  v_done uuid;
  v_result jsonb;
  v_project jsonb;
begin
  ${SERVICE}
  v_item := better_supabase.create_work_item('${TENANT}', '{"title": "Ship it", "dueAt": "2099-01-01T10:00:00Z"}'::jsonb, null);
  v_id := (v_item ->> 'id')::uuid;
  if (select seq from public.tickets where id = v_id) is null or (select code from public.tickets where id = v_id) is null then
    raise exception 'numbering %', v_item;
  end if;
  v_result := better_supabase.update_work_items(jsonb_build_array(
    jsonb_build_object('workItemId', v_id, 'field', 'title', 'value', 'Ship it now'),
    jsonb_build_object('workItemId', v_id, 'field', 'priority', 'value', 2)));
  if jsonb_array_length(v_result -> 'rejected') <> 0 then
    raise exception 'update %', v_result;
  end if;
  select s.id into v_done from better_supabase.pipeline_stages s
  where s.pipeline_id = (select pipeline_id from public.tickets where id = v_id) and s.key = 'done';
  v_result := better_supabase.update_work_items(jsonb_build_array(
    jsonb_build_object('workItemId', v_id, 'field', 'stageId', 'value', v_done)));
  if jsonb_array_length(v_result -> 'rejected') <> 0 then
    raise exception 'close %', v_result;
  end if;
  if (select state from public.tickets where id = v_id) <> 'completed'
    or (select close_reason from public.tickets where id = v_id) <> 'completed' then
    raise exception 'closed as % %', (select state from public.tickets where id = v_id), (select close_reason from public.tickets where id = v_id);
  end if;
  if jsonb_array_length(better_supabase.list_work_items('${TENANT}', '{"states": ["completed"]}'::jsonb, null, null, 50)) <> 1 then
    raise exception 'list_work_items missed the item';
  end if;
  v_project := better_supabase.save_project('${TENANT}', null, '{"key": "OPS", "name": "Ops"}'::jsonb);
  v_project := better_supabase.save_project('${TENANT}', (v_project ->> 'id')::uuid, '{"status": "active"}'::jsonb);
  if (select status from public.initiatives where code = 'OPS') <> 'active' then
    raise exception 'project %', v_project;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a field the app's table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.create_work_item('${TENANT}', '{"title": "Ship it", "estimate": 3}'::jsonb, null);
end;
$$;`),
    ).rejects.toThrow(/has no estimate column/);
  });
});

const USER = "22222222-2222-4222-8222-222222222222";

const AS_USER = `perform set_config('request.jwt.claims', '{"sub":"${USER}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${USER}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const ALLOW = `create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $f$ select true $f$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $f$ select '${TENANT}'::uuid $f$;`;

const NUMBERED: AnyBlocksConfig = {
  numbering: {
    options: {
      entities: {
        work_item: {
          period: "none",
          format: "T-{n}",
          table: "public.tickets",
          column: "code",
          sequenceColumn: "seq",
          tenantColumn: "org_id",
        },
      },
    },
  },
  tasks: {
    ...BLOCKS["tasks"],
    values: { items: { state: { backlog: "unstarted", triage: "backlog" } } },
  },
};

describe("tasks over the app's numbered tickets", BOOT, () => {
  it("numbers a member's item through the entity trigger and returns the block's keys", async () => {
    await expect(
      run(
        `${ALLOW}
do $$
declare
  v_item jsonb;
begin
  ${AS_USER}
  v_item := better_supabase.create_work_item('${TENANT}', '{"title": "Ship it"}'::jsonb, null);
  if v_item ->> 'identifier' <> 'T-1' or v_item ->> 'number' <> '1' then
    raise exception 'numbered %', v_item;
  end if;
  if v_item ->> 'tenant_id' <> '${TENANT}' or v_item ->> 'state' <> 'triage'
    or (select state::text from public.tickets where id = (v_item ->> 'id')::uuid) <> 'backlog' then
    raise exception 'keys %', v_item;
  end if;
  if current_setting('better_supabase.issued_number', true) <> '' then
    raise exception 'issued number left set';
  end if;
end;
$$;
do $$
begin
  ${AS_USER}
  insert into public.tickets (org_id, seq, code, title) values ('${TENANT}', 9, 'T-9', 'By hand');
  raise exception 'a hand-set number was accepted';
exception when insufficient_privilege then
  null;
end;
$$;`,
        NUMBERED,
        ["numbering"],
      ),
    ).resolves.toBeUndefined();
  });
});
