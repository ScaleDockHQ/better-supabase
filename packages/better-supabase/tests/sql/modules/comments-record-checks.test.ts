import { describe, expect, it } from "vitest";

import type {
  AnyBlocksConfig,
  SubjectsConfig,
} from "../../../src/config/index.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const FILE = "44444444-4444-4444-8444-444444444444";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create table public.files (
  id uuid primary key,
  organization_id uuid not null,
  owner_id uuid not null
);
`;

// Everyone reads files through file.read; only the owner comments and
// moderates. Nobody holds the messaging keys in the tenant.
const SUBJECTS: SubjectsConfig = {
  file: {
    table: "public.files",
    idType: "uuid",
    permissions: {
      read: "file.read",
      comment: { owner: "owner_id" },
      moderate: { owner: "owner_id" },
    },
  },
};

const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select permission = 'file.read' $$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select permission = 'file.read' $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid where permission = 'file.read' $$;
insert into public.files (id, organization_id, owner_id) values ('${FILE}', '${TENANT}', '${ALICE}');
`;

const as = (
  user: string,
) => `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const BOOT = { timeout: 60_000 };

const COMMENTS: AnyBlocksConfig = {
  comments: { options: { follow: false, notify: false } },
};

async function run(
  check: string,
  modules: AnyBlocksConfig = COMMENTS,
  subjects: SubjectsConfig = SUBJECTS,
): Promise<void> {
  const files = renderBlocks(["comments"], { subjects, modules });

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
      ALLOW,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("comments on a record that declares its own actions", BOOT, () => {
  it("lets the record's checks decide reading, commenting, editing and moderating", async () => {
    await expect(
      run(`do $$
declare
  v_comment jsonb;
  v_hint text;
begin
  ${as(ALICE)}
  v_comment := better_supabase.create_comment('${TENANT}', 'file', '${FILE}', 'first');
  perform better_supabase.edit_message((v_comment ->> 'id')::uuid, 'first, edited');
  ${as(BOB)}
  if jsonb_array_length(better_supabase.list_comments('${TENANT}', 'file', '${FILE}')) <> 1 then
    raise exception 'a reader of the file sees its comments';
  end if;
  begin
    perform better_supabase.create_comment('${TENANT}', 'file', '${FILE}', 'mine');
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint not like 'MESSAGING_FORBIDDEN' then
    raise exception 'a reader without comment rights commented: %', v_hint;
  end if;
  begin
    perform better_supabase.delete_message((v_comment ->> 'id')::uuid);
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint = 'none' then
    raise exception 'a non-moderator deleted a comment';
  end if;
  ${as(ALICE)}
  perform better_supabase.delete_message((v_comment ->> 'id')::uuid);
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("opens record conversations only on the types on allows", async () => {
    const subjects: SubjectsConfig = {
      file: { table: "public.files", idType: "uuid" },
      folder: { table: "public.files", idType: "uuid" },
    };

    const refused = (call: string, hint: string): string => `begin
    perform ${call};
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> '${hint}' then
    raise exception 'expected ${hint}, got %', v_hint;
  end if;`;

    await expect(
      run(
        `do $$
declare
  v_hint text;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform better_supabase.create_comment('${TENANT}', 'file', '${FILE}', 'on a file');
  perform better_supabase.open_conversation('${TENANT}', 'subject', jsonb_build_object('subjectType', 'file', 'subjectId', '${FILE}'));
  ${refused(`better_supabase.create_comment('${TENANT}', 'folder', '${FILE}', 'on a folder')`, "COMMENT_SUBJECT_UNSUPPORTED")}
  ${refused(`better_supabase.open_conversation('${TENANT}', 'subject', jsonb_build_object('subjectType', 'folder', 'subjectId', '${FILE}'))`, "MESSAGING_SUBJECT_UNSUPPORTED")}
end;
$$;`,
        {
          comments: { on: ["file"], options: { follow: false, notify: false } },
          messaging: { on: { file: {} } },
        },
        subjects,
      ),
    ).resolves.toBeUndefined();
  });
});
