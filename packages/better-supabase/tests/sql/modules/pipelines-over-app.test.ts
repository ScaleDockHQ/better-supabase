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

// The app's own pipeline and stage tables: renamed columns, an enum outcome,
// and no system key, color, probability, rotting, WIP limit or timestamps.
const APP = `
create type public.stage_outcome as enum ('open', 'success', 'failure');

create table public.boards (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  subject_type text not null,
  scope_id text,
  key text not null,
  name text not null,
  rank text not null default 'V',
  is_default boolean not null default false,
  archived_at timestamptz
);

create table public.board_columns (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  board_id uuid not null references public.boards (id) on delete cascade,
  key text not null,
  label text not null,
  rank text not null default 'V',
  category text not null,
  outcome public.stage_outcome not null,
  archived_at timestamptz
);
`;

const OWN_TABLES = {
  "public.boards": "app.sql",
  "public.board_columns": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  pipelines: {
    tables: { pipelines: "public.boards", stages: "public.board_columns" },
    columns: {
      pipelines: { tenant: "org_id", createdAt: null, updatedAt: null },
      stages: {
        tenant: "org_id",
        pipeline: "board_id",
        name: "label",
        systemKey: null,
        color: null,
        probability: null,
        rottingAfterDays: null,
        wipLimit: null,
        createdAt: null,
        updatedAt: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const blocks = [
    "memberships",
    "permissions",
    "subjects",
    "pipelines",
    "tasks",
  ];

  const files = renderBlocks(blocks, {
    modules: BLOCKS,
    ownTables: OWN_TABLES,
    subjects: withBlockSubjects({}, blocks, BLOCKS),
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

describe("pipelines over the app's tables", BOOT, () => {
  it("seeds, edits and reads stages in the app's tables without the optional columns", async () => {
    await expect(
      run(`do $$
declare
  v_item uuid;
  v_board uuid;
  v_type text;
  v_category text;
  v_done uuid;
  v_stage jsonb;
  v_list jsonb;
  v_result jsonb;
begin
  ${SERVICE}
  v_item := (better_supabase.create_task('${TENANT}', '{"title": "Ship it"}'::jsonb, null) ->> 'id')::uuid;
  select id, subject_type into v_board, v_type from public.boards;
  if v_board is null or (select count(*) from public.board_columns where board_id = v_board) = 0 then
    raise exception 'no default board';
  end if;
  select category into v_category from public.board_columns where board_id = v_board and outcome = 'open' order by rank limit 1;
  v_stage := better_supabase.save_pipeline_stage(v_board, null, 'review', 'Review', v_category, 50, 3, 2, 'blue');
  if v_stage ->> 'key' <> 'review' or v_stage ->> 'label' <> 'Review' or v_stage -> 'color' <> 'null'::jsonb then
    raise exception 'saved %', v_stage;
  end if;
  select id into v_done from public.board_columns where board_id = v_board and outcome = 'success' limit 1;
  v_result := better_supabase.update_tasks(jsonb_build_array(
    jsonb_build_object('workItemId', v_item, 'field', 'stageId', 'value', v_done)));
  if jsonb_array_length(v_result -> 'rejected') <> 0 then
    raise exception 'move %', v_result;
  end if;
  if (select count(*) from better_supabase.pipeline_stage_history where subject_id = v_item::text) <> 2 then
    raise exception 'history';
  end if;
  v_list := better_supabase.list_pipelines('${TENANT}', v_type);
  if jsonb_array_length(v_list) <> 1 or v_list -> 0 ->> 'id' <> v_board::text
    or not exists (select 1 from jsonb_array_elements(v_list -> 0 -> 'stages') x where x.value ->> 'key' = 'review') then
    raise exception 'listed %', v_list;
  end if;
  v_result := better_supabase.pipeline_board(v_type, v_board, null);
  if not exists (select 1 from jsonb_array_elements(v_result) x where (x.value ->> 'count')::integer = 1 and x.value -> 'wipLimit' = 'null'::jsonb) then
    raise exception 'board %', v_result;
  end if;
  if not better_supabase.archive_pipeline_stage((v_stage ->> 'id')::uuid) then
    raise exception 'archive';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
