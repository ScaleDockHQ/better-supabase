import { describe, expect, it } from "vitest";

import type { SubjectsConfig } from "../../../src/config/index.ts";

import { driveSubject } from "../../../src/blocks/drive/index.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";
import { ownTablesOf } from "../../fixtures/own-tables.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (
  blocks: readonly string[],
  module: string,
  layout: Layout = {},
): string =>
  renderBlocks(blocks, layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const REQUESTS: SubjectsConfig = {
  drive_node: driveSubject({ accessRequests: true }),
};

const WITH_REQUESTS = ["drive", "access-requests", "subjects", "notifications"];

describe("drive access requests", () => {
  it("grants the requested role on the node until the request ends", () => {
    const sql = sqlOf(["drive"], "drive");

    expect(sql).toContain(
      `create or replace function "better_supabase"."drive_grant_access"(subject_id text, user_id uuid, action text, ends_at timestamptz)`,
    );
    expect(sql).toContain(
      `revoke execute on function "better_supabase"."drive_grant_access"(text, uuid, text, timestamptz) from public, anon, authenticated;`,
    );
    expect(sql).toContain(`"access_request" boolean not null default false,`);
    expect(sql).toContain(
      `create or replace function "better_supabase"."drive_access_approvers"(subject_id text)`,
    );
    expect(sql).toContain(`and dg."access_request";`);
  });

  it("asks the node's sharers through access-requests", () => {
    const sql = sqlOf(WITH_REQUESTS, "access-requests", { subjects: REQUESTS });

    expect(sql).toContain("'drive_node'");
    expect(sql).toContain(`"better_supabase"."drive_grant_access"`);
    expect(sql).toContain(`"better_supabase"."drive_access_approvers"(`);
    expect(sql).toContain(
      `create or replace function "better_supabase"."list_record_access_requests"(subject_type text, subject_id text, status text default null, page_size integer default null)`,
    );
  });

  it("contributes nothing without a team on the drive subject", () => {
    const sql = sqlOf(WITH_REQUESTS, "access-requests", {
      subjects: { drive_node: driveSubject() },
    });

    expect(sql).not.toContain("drive_grant_access");
  });

  it("needs grants to decide access", () => {
    expect(() =>
      sqlOf(WITH_REQUESTS, "access-requests", {
        subjects: REQUESTS,
        modules: {
          drive: { options: { roleFunctions: { node: "public.node_role" } } },
        },
      }),
    ).toThrow("not blocks.drive.options.roleFunctions.node");

    const modules = {
      drive: {
        tables: { nodes: "public.file_node", grants: "public.file_node_grant" },
        columns: {
          nodes: {
            tenant: "organization_id",
            drive: null,
            attachment: null,
            path: null,
            rank: null,
            deletedAt: null,
          },
          grants: {
            tenant: "organization_id",
            node: "file_node_id",
            principalType: null,
            principalId: null,
            user: "user_id",
            team: "team_id",
            expiresAt: null,
            createdBy: null,
          },
        },
      },
    };

    expect(() =>
      sqlOf(WITH_REQUESTS, "access-requests", {
        subjects: {
          drive_node: driveSubject({
            schema: "public",
            table: "file_node",
            tenant: "organization_id",
            accessRequests: true,
          }),
        },
        modules,
        ownTables: ownTablesOf(modules),
      }),
    ).toThrow("blocks.drive.columns.grants.accessRequest and expiresAt");
  });
});

describe("drive ownership transfer", () => {
  it("moves the top-role grants and the drives a member owns", () => {
    const sql = sqlOf(["drive"], "drive", {
      modules: { drive: { options: { drives: true } } },
    });

    expect(sql).toContain(
      `create or replace function "better_supabase"."drive_transfer_ownership"(tenant uuid, from_user uuid, to_user uuid)`,
    );
    expect(sql).toContain("DRIVE_TRANSFER_INVALID");
    expect(sql).toContain(
      "drive_transfer_ownership.from_user is distinct from auth.uid()",
    );
    expect(sql).toContain(
      "'nodes', v_nodes, 'drives', v_drives, 'keptDriveIds', to_jsonb(v_kept)",
    );
    expect(sql).toContain(
      "exception when unique_violation or check_violation then",
    );
  });
});

const TENANT = "11111111-1111-4111-8111-111111111111";
const ANN = "22222222-2222-4222-8222-222222222222";
const BEN = "33333333-3333-4333-8333-333333333333";
const CAL = "44444444-4444-4444-8444-444444444444";

const STUB = `
do $$
declare r text;
begin
  foreach r in array array['anon', 'authenticated', 'service_role', 'supabase_auth_admin'] loop
    if not exists (select 1 from pg_roles where rolname = r) then
      execute format('create role %I', r);
    end if;
  end loop;
end;
$$;
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid $$;
create or replace function auth.jwt() returns jsonb language sql stable as
  $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create table if not exists auth.users (id uuid primary key);
create schema if not exists realtime;
create table if not exists realtime.messages (id bigint, topic text, extension text);
create function realtime.topic() returns text language sql stable as $$ select null::text $$;
create schema if not exists storage;
create table if not exists storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create function storage.foldername(name text) returns text[] language sql immutable as $$ select '{}'::text[] $$;
create table if not exists storage.objects (id uuid, bucket_id text, name text, owner uuid);
`;

describe("drive ownership transfer in Postgres", { timeout: 120_000 }, () => {
  it("keeps a personal drive the new owner can't take and moves the rest", async () => {
    const files = renderBlocks(["drive"], {
      modules: {
        drive: {
          options: { drives: true, driveKinds: ["shared", "personal"] },
        },
      },
    });

    await using stack = await liteStack({
      driver: "pglite",
      migrations: [
        STUB,
        ...files
          .filter((file) => file.kind === "schema")
          .map((file) => file.contents),
      ],
      seed: [
        ...files
          .filter((file) => file.kind === "data")
          .map((file) => file.contents),
        `insert into auth.users (id) values ('${ANN}'), ('${BEN}'), ('${CAL}') on conflict do nothing;
insert into better_supabase.memberships (organization_id, user_id, role)
select '${TENANT}', u, 'member' from unnest(array['${ANN}', '${BEN}', '${CAL}']::uuid[]) u
on conflict do nothing;
-- The app keeps one personal drive per owner and organization.
create unique index personal_drive_per_owner on better_supabase.drive_drives (tenant_id, owner_id) where kind = 'personal';
insert into better_supabase.drive_drives (tenant_id, name, kind, owner_id) values
  ('${TENANT}', 'Ann', 'personal', '${ANN}'),
  ('${TENANT}', 'Ann shared', 'shared', '${ANN}'),
  ('${TENANT}', 'Ben', 'personal', '${BEN}'),
  ('${TENANT}', 'Cal shared', 'shared', '${CAL}'),
  ('${TENANT}', 'Cal', 'personal', '${CAL}');
select set_config('request.jwt.claims', '{"role":"service_role"}', false);
do $$
declare
  v jsonb;
begin
  -- Ben already has a personal drive: Ann's stays with her, her shared one moves.
  v := better_supabase.drive_transfer_ownership('${TENANT}', '${ANN}', '${BEN}');
  if (v ->> 'drives')::integer <> 1
    or v -> 'keptDriveIds' <> to_jsonb(array(select id from better_supabase.drive_drives where name = 'Ann')) then
    raise exception 'the transfer to Ben returned %', v;
  end if;
  if (select owner_id from better_supabase.drive_drives where name = 'Ann') <> '${ANN}'
    or (select owner_id from better_supabase.drive_drives where name = 'Ann shared') <> '${BEN}' then
    raise exception 'the drives moved wrongly';
  end if;
  -- Ann has no other personal drive once Cal's is gone: Cal's moves to her.
  delete from better_supabase.drive_drives where name = 'Ann';
  v := better_supabase.drive_transfer_ownership('${TENANT}', '${CAL}', '${ANN}');
  if (v ->> 'drives')::integer <> 2 or v -> 'keptDriveIds' <> '[]'::jsonb
    or (select owner_id from better_supabase.drive_drives where name = 'Cal') <> '${ANN}' then
    raise exception 'the transfer to Ann returned %', v;
  end if;
end;
$$;`,
      ],
    });

    expect(stack.url).not.toBe("");
  });
});

describe("drive sharing policy", () => {
  it("renders nothing without the settings block", () => {
    const blocks = ["drive", "share-links", "guests"];

    expect(sqlOf(blocks, "drive")).not.toContain("drive_sharing");
    expect(sqlOf(blocks, "drive-files")).not.toContain("drive_sharing");
  });

  it("checks links and guest grants against drive.sharing", () => {
    const blocks = ["drive", "settings", "share-links", "guests"];
    const sql = sqlOf(blocks, "drive");
    const files = sqlOf(blocks, "drive-files");

    expect(sql).toContain(
      `create or replace function "better_supabase"."drive_sharing"(tenant uuid)`,
    );
    expect(sql).toContain(`'{"guests": true, "links": "anyone"}'::jsonb`);
    expect(files).toContain("this organization has turned off share links");
    expect(files).toContain(
      "sign in as a member of this organization to open this link",
    );
    expect(files).toContain(
      `create or replace function "better_supabase"."drive_guest_sharing"()`,
    );
    expect(files).toContain(
      "this organization has turned off sharing drive items with guests",
    );
  });
});
