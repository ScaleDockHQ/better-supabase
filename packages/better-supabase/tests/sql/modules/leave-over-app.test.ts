import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { adoptedColumnProblems } from "../../../src/sql/adopted-columns.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const DECIDER = "88888888-8888-4888-8888-888888888888";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own leave tables: renamed columns, enum unit and part, and no
// allowance, carryover, color, note or cancelled-by columns.
const APP = `
create type public.absence_unit as enum ('days', 'hours');
create type public.absence_part as enum ('full', 'morning', 'afternoon', 'hours');

create table public.absence_kinds (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  code text not null,
  label text not null,
  unit public.absence_unit not null default 'days',
  paid boolean not null default true,
  tracked boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.absences (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  user_id uuid not null,
  kind_id uuid not null references public.absence_kinds (id),
  starts_on date not null,
  ends_on date not null,
  part public.absence_part not null default 'full',
  days numeric not null,
  approval_id uuid,
  approved_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
`;

const OWN_TABLES = {
  "public.absence_kinds": "app.sql",
  "public.absences": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  leave: {
    tables: { types: "public.absence_kinds", requests: "public.absences" },
    columns: {
      types: {
        tenant: "org_id",
        key: "code",
        name: "label",
        allowance: null,
        carryoverMax: null,
        color: null,
      },
      requests: {
        tenant: "org_id",
        type: "kind_id",
        partial: "part",
        amount: "days",
        note: null,
        cancelledBy: null,
      },
    },
  },
};

// Everyone may do everything in the tenant: these tests are about the tables.
const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}');
insert into better_supabase.memberships (organization_id, user_id, role) values ('${TENANT}', '${ALICE}', 'owner');
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const AS_ALICE = `perform set_config('request.jwt.claims', '{"sub":"${ALICE}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${ALICE}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 120_000 };

async function run(
  check: string,
  modules: AnyBlocksConfig = BLOCKS,
  names: readonly string[] = ["leave"],
  app: string = APP,
): Promise<void> {
  const files = renderBlocks(names, { modules, ownTables: OWN_TABLES });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      app,
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

describe("leave over the app's tables", BOOT, () => {
  it("saves a type, books, approves and cancels leave in enum columns", async () => {
    await expect(
      run(`do $$
declare
  v_type jsonb;
  v_type_id uuid;
  v_request jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_type := better_supabase.save_leave_type('${TENANT}', 'vacation', 'Vacation');
  v_type_id := (v_type ->> 'id')::uuid;
  v_type := better_supabase.save_leave_type('${TENANT}', 'vacation', 'Holiday', 'days');
  if (v_type ->> 'id')::uuid <> v_type_id or (select label from public.absence_kinds where id = v_type_id) <> 'Holiday' then
    raise exception 'saved %', v_type;
  end if;
  perform better_supabase.adjust_leave_balance('${TENANT}', '${ALICE}', v_type_id, 10, 2099);
  ${AS_ALICE}
  v_request := better_supabase.request_leave('${TENANT}', v_type_id, '2099-03-02', '2099-03-08');
  v_id := (v_request ->> 'id')::uuid;
  if (select part from public.absences where id = v_id) <> 'full' or (select days from public.absences where id = v_id) <> 5 then
    raise exception 'requested %', v_request;
  end if;
  perform better_supabase.approve_leave_request(v_id);
  if (select approved_at from public.absences where id = v_id) is null then
    raise exception 'not approved';
  end if;
  ${SERVICE}
  v_request := better_supabase.cancel_leave_request(v_id);
  if (select cancelled_at from public.absences where id = v_id) is null then
    raise exception 'not cancelled %', v_request;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("runs without a type key or a partial column", async () => {
    const leave = BLOCKS["leave"];

    await expect(
      run(
        `do $$
declare
  v_type jsonb;
  v_type_id uuid;
  v_request jsonb;
begin
  ${SERVICE}
  v_type := better_supabase.save_leave_type('${TENANT}', 'vacation', 'Vacation');
  v_type_id := (v_type ->> 'id')::uuid;
  if v_type ->> 'key' <> v_type_id::text then
    raise exception 'key %', v_type;
  end if;
  v_type := better_supabase.save_leave_type('${TENANT}', v_type_id::text, 'Holiday');
  if (v_type ->> 'id')::uuid <> v_type_id or (select count(*) from public.absence_kinds) <> 1
    or (select label from public.absence_kinds) <> 'Holiday' then
    raise exception 'updated %', v_type;
  end if;
  perform better_supabase.adjust_leave_balance('${TENANT}', '${ALICE}', v_type_id, 10, 2099);
  ${AS_ALICE}
  v_request := better_supabase.request_leave('${TENANT}', v_type_id, '2099-03-02', '2099-03-03');
  if v_request ->> 'partial' <> 'full' or (v_request ->> 'amount')::numeric <> 2 then
    raise exception 'requested %', v_request;
  end if;
  begin
    perform better_supabase.request_leave('${TENANT}', v_type_id, '2099-03-09', '2099-03-09', 'morning');
    raise exception 'a half day was accepted';
  exception when others then
    if sqlerrm not like '%no partial column%' then
      raise;
    end if;
  end;
end;
$$;`,
        {
          leave: {
            ...leave,
            columns: {
              types: { ...leave?.columns?.["types"], key: null },
              requests: { ...leave?.columns?.["requests"], partial: null },
            },
          },
        },
        ["leave"],
        APP.replace("  code text not null,\n", "").replace(
          "  part public.absence_part not null default 'full',\n",
          "",
        ),
      ),
    ).resolves.toBeUndefined();
  });

  it("reopens the approval of a changed request and books types without approval on the block's tables", async () => {
    await expect(
      run(
        `do $$
declare
  v_holiday uuid;
  v_sick uuid;
  v_request jsonb;
  v_approval uuid;
begin
  ${SERVICE}
  v_holiday := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday') ->> 'id')::uuid;
  v_sick := (better_supabase.save_leave_type('${TENANT}', 'sick', 'Sick', 'days', true, false, auto_approve => true) ->> 'id')::uuid;
  perform better_supabase.adjust_leave_balance('${TENANT}', '${ALICE}', v_holiday, 10, 2099);
  ${AS_ALICE}
  v_request := better_supabase.request_leave('${TENANT}', v_holiday, '2099-03-02', '2099-03-03');
  v_approval := (v_request ->> 'approvalId')::uuid;
  v_request := better_supabase.update_leave_request((v_request ->> 'id')::uuid, ends_on => '2099-03-04');
  if v_request ->> 'status' <> 'pending' or (v_request ->> 'approvalId')::uuid = v_approval
    or (select status from better_supabase.approval_requests where id = v_approval) <> 'cancelled'
    or (v_request ->> 'amount')::numeric <> 3 then
    raise exception 'changed %', v_request;
  end if;
  v_request := better_supabase.request_leave('${TENANT}', v_sick, '2099-03-09', '2099-03-09');
  if v_request ->> 'status' <> 'approved' or v_request ->> 'approvalId' is not null then
    raise exception 'sick %', v_request;
  end if;
end;
$$;`,
        {},
        ["leave"],
        "",
      ),
    ).resolves.toBeUndefined();
  });

  it("sends a requester's change to approved leave back to approval when configured", async () => {
    const APPROVER = "99999999-9999-4999-8999-999999999999";

    const denied = (
      keys: readonly string[],
    ): string => `create table public.denied (permission text primary key);
insert into public.denied values ${keys.map((key) => `('${key}')`).join(", ")};
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select not exists (select 1 from public.denied d where d.permission = can.permission) $$;
insert into auth.users (id) values ('${APPROVER}');
insert into better_supabase.memberships (organization_id, user_id, role) values ('${TENANT}', '${APPROVER}', 'member');`;

    const asApprover = `perform set_config('request.jwt.claims', '{"sub":"${APPROVER}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${APPROVER}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

    const flow = (
      keys: readonly string[],
      change: string,
    ): string => `${denied(keys)}
do $$
declare
  v_holiday uuid;
  v_request jsonb;
  v_first uuid;
  v_balance jsonb;
begin
  ${SERVICE}
  v_holiday := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday') ->> 'id')::uuid;
  perform better_supabase.adjust_leave_balance('${TENANT}', '${ALICE}', v_holiday, 10, 2099);
  ${AS_ALICE}
  v_request := better_supabase.request_leave('${TENANT}', v_holiday, '2099-03-02', '2099-03-03');
  v_first := (v_request ->> 'approvalId')::uuid;
  ${asApprover}
  perform better_supabase.decide_approval(v_first, 'approved');
  ${AS_ALICE}
  ${change}
end;
$$;`;

    const reapproved = `v_request := better_supabase.update_leave_request((v_request ->> 'id')::uuid, ends_on => '2099-03-04');
  v_balance := better_supabase.leave_balances('${TENANT}', '${ALICE}', 2099) -> 0;
  if v_request ->> 'status' <> 'pending' or v_request ->> 'approvedAt' is not null
    or (v_request ->> 'approvalId')::uuid = v_first
    or (v_balance ->> 'available')::numeric <> 7 or (v_balance ->> 'pending')::numeric <> 3 then
    raise exception 'reapproval % %', v_request, v_balance;
  end if;
  ${asApprover}
  perform better_supabase.decide_approval((v_request ->> 'approvalId')::uuid, 'approved');
  v_balance := better_supabase.leave_balances('${TENANT}', '${ALICE}', 2099) -> 0;
  if (v_balance ->> 'available')::numeric <> 7 or (v_balance ->> 'pending')::numeric <> 0 then
    raise exception 'approved again %', v_balance;
  end if;`;

    const change = `perform better_supabase.update_leave_request((v_request ->> 'id')::uuid, ends_on => '2099-03-04');`;

    await expect(
      run(
        flow(["leave.manage"], reapproved),
        { leave: { options: { reapprove: true } } },
        ["leave"],
        "",
      ),
    ).resolves.toBeUndefined();
    await expect(
      run(
        flow(["leave.manage"], reapproved),
        { leave: { permissions: { reapprove: "leave.reapprove" } } },
        ["leave"],
        "",
      ),
    ).resolves.toBeUndefined();
    await expect(
      run(
        flow(["leave.manage", "leave.reapprove"], change),
        { leave: { permissions: { reapprove: "leave.reapprove" } } },
        ["leave"],
        "",
      ),
    ).rejects.toThrow(/changed by a manager/);
    await expect(
      run(flow(["leave.manage"], change), {}, ["leave"], ""),
    ).rejects.toThrow(/changed by a manager/);
  });

  it("clears the decision of reapproved leave without the approvals block", async () => {
    const leave = BLOCKS["leave"];

    await expect(
      run(
        `create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select can.permission <> 'leave.manage' $$;
do $$
declare
  v_type_id uuid;
  v_id uuid;
  v_request jsonb;
begin
  ${SERVICE}
  v_type_id := (better_supabase.save_leave_type('${TENANT}', 'vacation', 'Vacation') ->> 'id')::uuid;
  perform better_supabase.adjust_leave_balance('${TENANT}', '${ALICE}', v_type_id, 10, 2099);
  ${AS_ALICE}
  v_id := (better_supabase.request_leave('${TENANT}', v_type_id, '2099-03-02', '2099-03-03') ->> 'id')::uuid;
  ${SERVICE}
  perform better_supabase.decide_leave_request(v_id, true, 'enjoy');
  ${AS_ALICE}
  v_request := better_supabase.update_leave_request(v_id, ends_on => '2099-03-04');
  if v_request ->> 'status' <> 'pending'
    or (select row(approved_at, decided_by, decision_note)::text from public.absences where id = v_id) <> '(,,)'
    or (better_supabase.leave_balances('${TENANT}', '${ALICE}', 2099) -> 0 ->> 'available')::numeric <> 7 then
    raise exception 'reapproval %', v_request;
  end if;
end;
$$;`,
        {
          leave: {
            ...leave,
            columns: {
              ...leave?.columns,
              requests: { ...leave?.columns?.["requests"], approval: null },
            },
            options: { approvals: false, reapprove: true },
          },
        },
        ["leave"],
        APP.replace(
          "  approval_id uuid,",
          "  rejected_at timestamptz,\n  decided_by uuid,\n  decision_note text,",
        ),
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses a note the app's table has no column for", async () => {
    await expect(
      run(`do $$
declare
  v_type_id uuid;
begin
  ${SERVICE}
  v_type_id := (better_supabase.save_leave_type('${TENANT}', 'vacation', 'Vacation') ->> 'id')::uuid;
  perform better_supabase.adjust_leave_balance('${TENANT}', '${ALICE}', v_type_id, 10, 2099);
  ${AS_ALICE}
  perform better_supabase.request_leave('${TENANT}', v_type_id, '2099-03-02', '2099-03-08', 'full', null, 'beach');
end;
$$;`),
    ).rejects.toThrow(/no note column/);
  });

  it("decides requests without the approvals block and shares approved leave as a feed", async () => {
    const leave = BLOCKS["leave"];

    await expect(
      run(
        `do $$
declare
  v_type_id uuid;
  v_first uuid;
  v_second uuid;
  v_request jsonb;
  v_link jsonb;
  v_feed jsonb;
  v_old_token text;
  v_link_id uuid;
begin
  ${SERVICE}
  v_type_id := (better_supabase.save_leave_type('${TENANT}', 'vacation', 'Vacation') ->> 'id')::uuid;
  perform better_supabase.adjust_leave_balance('${TENANT}', '${ALICE}', v_type_id, 10, 2099);
  ${AS_ALICE}
  v_first := (better_supabase.request_leave('${TENANT}', v_type_id, '2099-03-02', '2099-03-03') ->> 'id')::uuid;
  v_second := (better_supabase.request_leave('${TENANT}', v_type_id, '2099-04-06', '2099-04-07') ->> 'id')::uuid;
  if (better_supabase.leave_balances('${TENANT}', '${ALICE}', 2099) -> 0 ->> 'pending')::numeric <> 4 then
    raise exception 'pending %', better_supabase.leave_balances('${TENANT}', '${ALICE}', 2099);
  end if;
  begin
    perform better_supabase.decide_leave_request(v_first, true, null);
    raise exception 'decided own request';
  exception when others then
    if sqlerrm = 'decided own request' then
      raise;
    end if;
  end;
  ${SERVICE}
  begin
    perform better_supabase.decide_leave_request(v_first, true, null, '${ALICE}');
    raise exception 'decided for the requester';
  exception when others then
    if sqlerrm not like '%never for the requester%' then
      raise;
    end if;
  end;
  v_request := better_supabase.decide_leave_request(v_first, true, 'enjoy', '${DECIDER}');
  if v_request ->> 'status' <> 'approved' or (select decision_note from public.absences where id = v_first) <> 'enjoy'
    or (select decided_by from public.absences where id = v_first) <> '${DECIDER}' then
    raise exception 'approved %', v_request;
  end if;
  v_request := better_supabase.decide_leave_request(v_second, false, 'busy month');
  if v_request ->> 'status' <> 'rejected' or (select rejected_at from public.absences where id = v_second) is null then
    raise exception 'rejected %', v_request;
  end if;
  if (better_supabase.leave_balances('${TENANT}', '${ALICE}', 2099) -> 0 ->> 'available')::numeric <> 8 then
    raise exception 'balance %', better_supabase.leave_balances('${TENANT}', '${ALICE}', 2099);
  end if;
  ${AS_ALICE}
  v_link := better_supabase.create_share_link('${TENANT}', 'leave_feed', '${TENANT}', 'view');
  v_old_token := v_link ->> 'token';
  v_link := better_supabase.create_share_link('${TENANT}', 'leave_feed', '${TENANT}', 'view');
  v_link_id := (v_link ->> 'id')::uuid;
  if better_supabase.leave_feed(v_old_token) is not null then
    raise exception 'the replaced leave feed remained live';
  end if;
  v_feed := better_supabase.leave_feed(v_link ->> 'token');
  if jsonb_array_length(v_feed -> 'requests') <> 1 or v_feed -> 'requests' -> 0 ->> 'id' <> v_first::text then
    raise exception 'feed %', v_feed;
  end if;
  if (select use_count from better_supabase.share_links where id = v_link_id) <> 1
    or (select last_used_at from better_supabase.share_links where id = v_link_id) is null then
    raise exception 'leave feed access was not recorded';
  end if;
  if better_supabase.leave_feed(repeat('0', 48)) is not null then
    raise exception 'an unknown token read the feed';
  end if;
end;
$$;`,
        {
          leave: {
            ...leave,
            columns: {
              ...leave?.columns,
              requests: { ...leave?.columns?.["requests"], approval: null },
            },
            options: { approvals: false },
          },
        },
        ["leave", "share-links"],
        `${APP.replace(
          "  approval_id uuid,",
          "  rejected_at timestamptz,\n  decided_by uuid,\n  decision_note text,",
        )}
create schema if not exists extensions;
create or replace function extensions.gen_random_bytes(n integer) returns bytea
language sql volatile as $$ select decode(md5(random()::text) || md5(random()::text), 'hex') $$;
create or replace function extensions.digest(data bytea, type text) returns bytea
language sql immutable as $$ select sha256(data) $$;
`,
      ),
    ).resolves.toBeUndefined();
  });
});

describe("confidential leave types", BOOT, () => {
  it("hides confidential leave from readers without the key, keeps it for its owner and in the feed only for holders", async () => {
    const leave = BLOCKS["leave"];
    const reader = "33333333-3333-4333-8333-333333333333";
    const asReader = AS_ALICE.replaceAll(ALICE, reader);

    await expect(
      run(
        `create table public.denied (user_id uuid, permission text);
insert into public.denied values ('${reader}', 'leave.manage');
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select not exists (select 1 from public.denied d where d.user_id = auth.uid() and d.permission = can.permission) $$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select not exists (select 1 from public.denied d where d.user_id = can_user.member and d.permission = can_user.permission) $$;
insert into auth.users (id) values ('${reader}');
insert into better_supabase.memberships (organization_id, user_id, role) values ('${TENANT}', '${reader}', 'member');
do $$
declare
  v_vacation uuid;
  v_sick uuid;
  v_link jsonb;
begin
  ${SERVICE}
  v_vacation := (better_supabase.save_leave_type('${TENANT}', 'vacation', 'Vacation') ->> 'id')::uuid;
  v_sick := (better_supabase.save_leave_type('${TENANT}', 'sick', 'Sick') ->> 'id')::uuid;
  update public.absence_kinds set confidential = true where id = v_sick;
  perform better_supabase.adjust_leave_balance('${TENANT}', '${ALICE}', v_vacation, 10, 2099);
  perform better_supabase.adjust_leave_balance('${TENANT}', '${ALICE}', v_sick, 10, 2099);
  ${AS_ALICE}
  perform better_supabase.approve_leave_request((better_supabase.request_leave('${TENANT}', v_vacation, '2099-03-02', '2099-03-03') ->> 'id')::uuid);
  perform better_supabase.approve_leave_request((better_supabase.request_leave('${TENANT}', v_sick, '2099-04-06', '2099-04-07') ->> 'id')::uuid);
  if jsonb_array_length(better_supabase.list_leave_requests('${TENANT}', everyone => true)) <> 2
    or jsonb_array_length(better_supabase.leave_balances('${TENANT}', '${ALICE}', 2099)) <> 2 then
    raise exception 'the owner lost confidential leave';
  end if;
  ${asReader}
  if jsonb_array_length(better_supabase.list_leave_requests('${TENANT}', everyone => true)) <> 1
    or jsonb_array_length(better_supabase.list_leave_requests('${TENANT}', user_id => '${ALICE}')) <> 1
    or jsonb_array_length(better_supabase.leave_balances('${TENANT}', '${ALICE}', 2099)) <> 1
    or exists (select 1 from jsonb_array_elements(better_supabase.leave_ledger_entries('${TENANT}', '${ALICE}', 2099)) e where e ->> 'typeId' = v_sick::text) then
    raise exception 'a reader without the key saw confidential leave';
  end if;
  v_link := better_supabase.create_share_link('${TENANT}', 'leave_feed', '${TENANT}', 'view');
  if jsonb_array_length(better_supabase.leave_feed(v_link ->> 'token') -> 'requests') <> 1 then
    raise exception 'the feed of a reader without the key showed confidential leave';
  end if;
  delete from public.denied;
  if jsonb_array_length(better_supabase.list_leave_requests('${TENANT}', everyone => true)) <> 2
    or jsonb_array_length(better_supabase.leave_feed(v_link ->> 'token') -> 'requests') <> 2 then
    raise exception 'a holder of the key missed confidential leave';
  end if;
end;
$$;`,
        {
          leave: {
            ...leave,
            columns: {
              ...leave?.columns,
              types: {
                ...leave?.columns?.["types"],
                confidential: "confidential",
              },
            },
          },
        },
        ["leave", "share-links"],
        `${APP.replace(
          "  tracked boolean not null default true,",
          "  tracked boolean not null default true,\n  confidential boolean not null default false,",
        )}
create schema if not exists extensions;
create or replace function extensions.gen_random_bytes(n integer) returns bytea
language sql volatile as $$ select decode(md5(random()::text) || md5(random()::text), 'hex') $$;
create or replace function extensions.digest(data bytea, type text) returns bytea
language sql immutable as $$ select sha256(data) $$;
`,
      ),
    ).resolves.toBeUndefined();
  });

  it("matches hidden feed types on a named column and names employees with a split name", () => {
    const sql = renderBlocks(["leave", "employees", "share-links"], {
      modules: {
        leave: {
          options: {
            feed: { names: true, hideTypes: ["sick"], typeKey: "category" },
          },
        },
        employees: { options: { name: "split" } },
      },
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(`t."category"::text = any ('{sick}'::text[])`);
    expect(sql).toContain(`concat_ws(' ', y."first_name"`);
    expect(() =>
      renderBlocks(["leave", "share-links"], {
        modules: { leave: { options: { feed: { typeKey: "Bad Name" } } } },
      }),
    ).toThrow(/typeKey/);
  });

  it("checks the readConfidential key when the config names one", () => {
    const leave = BLOCKS["leave"];

    const sql = renderBlocks(["leave"], {
      modules: {
        leave: {
          ...leave,
          columns: {
            ...leave?.columns,
            types: {
              ...leave?.columns?.["types"],
              confidential: "confidential",
            },
          },
          permissions: { readConfidential: "leave.sickness" },
        },
      },
      ownTables: OWN_TABLES,
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("'leave.sickness'");
    expect(
      renderBlocks(["leave"], { modules: {} })
        .map((file) => file.contents)
        .join("\n"),
    ).not.toContain("lc.");
    expect(() =>
      renderBlocks(["leave"], {
        modules: { leave: { columns: { types: { confidential: "secret" } } } },
      }),
    ).toThrow(/confidential/);
  });
});

const BOB = "33333333-3333-4333-8333-333333333333";
const ALICE_EMPLOYEE = "55555555-5555-4555-8555-555555555555";
const BOB_EMPLOYEE = "66666666-6666-4666-8666-666666666666";
const NO_ACCOUNT = "77777777-7777-4777-8777-777777777777";

const STAFF = `
insert into auth.users (id) values ('${BOB}');
insert into better_supabase.employees (id, tenant_id, user_id, name, manager_id) values
  ('${BOB_EMPLOYEE}', '${TENANT}', '${BOB}', 'Bob', null),
  ('${ALICE_EMPLOYEE}', '${TENANT}', '${ALICE}', 'Alice', '${BOB_EMPLOYEE}'),
  ('${NO_ACCOUNT}', '${TENANT}', null, 'Dana', '${BOB_EMPLOYEE}');
`;

const EMPLOYEE_APP = `
create type public.time_off_part as enum ('full', 'morning', 'afternoon', 'hours');
create type public.time_off_entry_kind as enum ('grant', 'accrual', 'taken', 'adjustment', 'carryover', 'expiry');

create table public.time_off_types (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text not null,
  unit text not null default 'hours',
  paid boolean not null default true,
  deducts_balance boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.time_off_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  employee_id uuid not null,
  time_off_type_id uuid not null references public.time_off_types (id),
  starts_on date not null,
  ends_on date not null,
  start_part public.time_off_part not null default 'full',
  end_part public.time_off_part not null default 'full',
  hours numeric(7, 2) not null,
  note text,
  approved_at timestamptz,
  rejected_at timestamptz,
  decided_by uuid,
  decision_note text,
  canceled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.time_off_ledger (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  employee_id uuid not null,
  time_off_type_id uuid not null,
  kind public.time_off_entry_kind not null,
  hours numeric(8, 2) not null,
  effective_on date not null,
  expires_on date,
  time_off_request_id uuid,
  note text,
  created_by uuid,
  created_at timestamptz not null default now()
);
`;

const EMPLOYEE_OWN = {
  "public.time_off_types": "app.sql",
  "public.time_off_requests": "app.sql",
  "public.time_off_ledger": "app.sql",
};

const EMPLOYEE_BLOCKS: AnyBlocksConfig = {
  leave: {
    tables: {
      types: "public.time_off_types",
      requests: "public.time_off_requests",
      balances: "public.time_off_ledger",
    },
    columns: {
      types: {
        tenant: "organization_id",
        key: null,
        tracked: "deducts_balance",
        allowance: null,
        carryoverMax: null,
        color: null,
      },
      requests: {
        tenant: "organization_id",
        user: null,
        employee: "employee_id",
        type: "time_off_type_id",
        partial: null,
        startPart: "start_part",
        endPart: "end_part",
        amount: "hours",
        approval: null,
        cancelledAt: "canceled_at",
        cancelledBy: null,
      },
      balances: {
        tenant: "organization_id",
        user: null,
        employee: "employee_id",
        type: "time_off_type_id",
        amount: "hours",
        request: "time_off_request_id",
        key: null,
      },
    },
    options: { owner: "employee", approvals: false },
  },
};

const AS = (
  user: string,
): string => `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

async function runEmployees(
  check: string,
  modules: AnyBlocksConfig,
  ownTables: Readonly<Record<string, string>>,
  app: string,
): Promise<void> {
  const files = renderBlocks(["employees", "leave"], { modules, ownTables });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      app,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      ALLOW,
      STAFF,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("leave by employee over the app's requests and balances", BOOT, () => {
  it("adopts the tables without problems", () => {
    expect(
      adoptedColumnProblems(
        EMPLOYEE_BLOCKS,
        [{ text: EMPLOYEE_APP }],
        ["public"],
        EMPLOYEE_OWN,
      ),
    ).toEqual([]);
  });

  it("books half days and hours for employees with and without accounts against the app's balances", async () => {
    await expect(
      runEmployees(
        `do $$
declare
  v_type uuid;
  v_request jsonb;
  v_first uuid;
  v_second uuid;
  v_balances jsonb;
begin
  ${SERVICE}
  v_type := (better_supabase.save_leave_type('${TENANT}', 'vacation', 'Vacation', 'hours') ->> 'id')::uuid;
  perform better_supabase.adjust_leave_balance('${TENANT}', null, v_type, 40, 2099, 'grant', 'yearly', employee_id => '${ALICE_EMPLOYEE}');
  perform better_supabase.adjust_leave_balance('${TENANT}', null, v_type, 8, 2099, 'grant', null, employee_id => '${ALICE_EMPLOYEE}', expires_on => '2099-01-31');
  perform better_supabase.adjust_leave_balance('${TENANT}', null, v_type, 16, 2099, 'grant', null, employee_id => '${NO_ACCOUNT}');
  ${AS(ALICE)}
  v_request := better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-04', 'full', 20, null, start_part => 'afternoon', end_part => 'morning');
  v_first := (v_request ->> 'id')::uuid;
  if v_request ->> 'employeeId' <> '${ALICE_EMPLOYEE}' or v_request ->> 'startPart' <> 'afternoon' or v_request ->> 'endPart' <> 'morning'
    or (select hours from public.time_off_requests where id = v_first) <> 20
    or (select start_part from public.time_off_requests where id = v_first) <> 'afternoon' then
    raise exception 'requested %', v_request;
  end if;
  v_second := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-04', '2099-03-04', 'full', 4, null, start_part => 'afternoon', end_part => 'full') ->> 'id')::uuid;
  begin
    perform better_supabase.request_leave('${TENANT}', v_type, '2099-03-03', '2099-03-03', 'full', 8);
    raise exception 'an overlapping day was accepted';
  exception when others then
    if sqlerrm not like '%overlaps%' then
      raise;
    end if;
  end;
  begin
    perform better_supabase.request_leave('${TENANT}', v_type, '2099-03-09', '2099-03-09', 'full', 8, employee_id => '${NO_ACCOUNT}');
    raise exception 'requested for another employee';
  exception when others then
    if sqlerrm not like '%another employee%' then
      raise;
    end if;
  end;
  ${AS(BOB)}
  perform better_supabase.request_leave('${TENANT}', v_type, '2099-03-09', '2099-03-09', 'full', 8, employee_id => '${NO_ACCOUNT}');
  if jsonb_array_length(better_supabase.list_leave_requests('${TENANT}', employee_id => '${ALICE_EMPLOYEE}')) <> 2 then
    raise exception 'manager list %', better_supabase.list_leave_requests('${TENANT}', employee_id => '${ALICE_EMPLOYEE}');
  end if;
  perform better_supabase.decide_leave_request(v_first, true, 'enjoy');
  if (select count(*) from public.time_off_ledger where time_off_request_id = v_first and kind = 'taken' and hours = -20) <> 1 then
    raise exception 'taken not posted';
  end if;
  ${AS(ALICE)}
  v_balances := better_supabase.leave_balances('${TENANT}', null, 2099);
  if (v_balances -> 0 ->> 'available')::numeric <> 24 or (v_balances -> 0 ->> 'taken')::numeric <> 20
    or v_balances -> 0 ->> 'employeeId' <> '${ALICE_EMPLOYEE}' then
    raise exception 'balances %', v_balances;
  end if;
  if jsonb_array_length(better_supabase.leave_ledger_entries('${TENANT}', null, 2099)) <> 3 then
    raise exception 'entries %', better_supabase.leave_ledger_entries('${TENANT}', null, 2099);
  end if;
  ${SERVICE}
  perform better_supabase.cancel_leave_request(v_first);
  if exists (select 1 from public.time_off_ledger where time_off_request_id = v_first) then
    raise exception 'taken kept after cancel';
  end if;
  if (better_supabase.leave_balances('${TENANT}', null, 2099, employee_id => '${NO_ACCOUNT}') -> 0 ->> 'pending')::numeric <> 8 then
    raise exception 'no account balance %', better_supabase.leave_balances('${TENANT}', null, 2099, employee_id => '${NO_ACCOUNT}');
  end if;
  begin
    perform better_supabase.request_leave('${TENANT}', v_type, '2099-04-01', '2099-04-10', 'full', 100, employee_id => '${ALICE_EMPLOYEE}');
    raise exception 'an overdraft was accepted';
  exception when others then
    if sqlerrm not like '%available balance%' then
      raise;
    end if;
  end;
  perform v_second;
end;
$$;`,
        EMPLOYEE_BLOCKS,
        EMPLOYEE_OWN,
        EMPLOYEE_APP,
      ),
    ).resolves.toBeUndefined();
  });

  it("changes, shortens and splits leave and approves types that need no approval", async () => {
    const leave = EMPLOYEE_BLOCKS["leave"];

    await expect(
      runEmployees(
        `do $$
declare
  v_days uuid;
  v_sick uuid;
  v_id uuid;
  v_request jsonb;
  v_split jsonb;
begin
  ${SERVICE}
  v_days := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday', 'days') ->> 'id')::uuid;
  v_sick := (better_supabase.save_leave_type('${TENANT}', 'sick', 'Sick', 'days', true, false, auto_approve => true) ->> 'id')::uuid;
  if not (select auto_approve from public.time_off_types where id = v_sick) then
    raise exception 'auto approve not saved';
  end if;
  perform better_supabase.adjust_leave_balance('${TENANT}', null, v_days, 20, 2099, 'grant', null, employee_id => '${ALICE_EMPLOYEE}');
  ${AS(ALICE)}
  v_id := (better_supabase.request_leave('${TENANT}', v_days, '2099-03-02', '2099-03-06') ->> 'id')::uuid;
  v_request := better_supabase.update_leave_request(v_id, ends_on => '2099-03-04', note => 'shorter');
  if v_request ->> 'status' <> 'pending' or (select row(hours, note)::text from public.time_off_requests where id = v_id) <> '(3.00,shorter)' then
    raise exception 'pending change %', v_request;
  end if;
  ${AS(BOB)}
  perform better_supabase.decide_leave_request(v_id, true, null);
  v_request := better_supabase.update_leave_request(v_id, ends_on => '2099-03-13');
  if (select sum(hours) from public.time_off_ledger where time_off_request_id = v_id and kind = 'taken') <> -10 then
    raise exception 'approved change %', (select jsonb_agg(row_to_json(l)) from public.time_off_ledger l);
  end if;
  v_split := better_supabase.split_leave_request(v_id, '2099-03-05', '2099-03-06');
  if (select row(ends_on, hours)::text from public.time_off_requests where id = v_id) <> '(2099-03-04,3.00)'
    or v_split -> 'split' ->> 'status' <> 'approved' or (v_split -> 'split' ->> 'amount')::numeric <> 5
    or v_split -> 'split' ->> 'startsOn' <> '2099-03-07' then
    raise exception 'split %', v_split;
  end if;
  if (select sum(hours) from public.time_off_ledger where employee_id = '${ALICE_EMPLOYEE}' and kind = 'taken') <> -8 then
    raise exception 'split taken %', (select jsonb_agg(row_to_json(l)) from public.time_off_ledger l);
  end if;
  ${AS(ALICE)}
  v_request := better_supabase.request_leave('${TENANT}', v_sick, '2099-03-05', '2099-03-06');
  if v_request ->> 'status' <> 'approved' then
    raise exception 'sick leave waited %', v_request;
  end if;
end;
$$;`,
        {
          leave: {
            ...leave,
            columns: {
              ...leave?.columns,
              types: {
                ...leave?.columns?.["types"],
                autoApprove: "auto_approve",
              },
            },
          },
        },
        EMPLOYEE_OWN,
        EMPLOYEE_APP.replace(
          "  deducts_balance boolean not null default true,",
          "  deducts_balance boolean not null default true,\n  auto_approve boolean not null default false,",
        ),
      ),
    ).resolves.toBeUndefined();
  });

  it("shares one team's leave with names, parts and fields, and hides configured types", async () => {
    const files = renderBlocks(["employees", "teams", "leave", "share-links"], {
      modules: {
        employees: {},
        leave: {
          options: {
            owner: "employee",
            extraColumns: { reason: "text" },
            feed: {
              teams: true,
              names: true,
              fields: true,
              hideTypes: ["sick"],
            },
          },
        },
      },
    });

    await using stack = await liteStack({
      driver: "pglite",
      migrations: [
        ROLES,
        `create schema if not exists extensions;
create or replace function extensions.gen_random_bytes(n integer) returns bytea
language sql volatile as $$ select decode(md5(random()::text) || md5(random()::text), 'hex') $$;
create or replace function extensions.digest(data bytea, type text) returns bytea
language sql immutable as $$ select sha256(data) $$;`,
        ...files
          .filter((file) => file.kind !== "data")
          .map((file) => file.contents),
      ],
      seed: [
        ...files
          .filter((file) => file.kind === "data")
          .map((file) => file.contents),
        ALLOW,
        STAFF,
        `insert into better_supabase.teams (id, tenant_id, name, slug) values ('88888888-8888-4888-8888-888888888888', '${TENANT}', 'Support', 'support');
insert into better_supabase.team_members (team_id, user_id, tenant_id) values ('88888888-8888-4888-8888-888888888888', '${ALICE}', '${TENANT}');`,
        `do $$
declare
  v_holiday uuid;
  v_sick uuid;
  v_link jsonb;
  v_feed jsonb;
begin
  ${SERVICE}
  v_holiday := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday') ->> 'id')::uuid;
  v_sick := (better_supabase.save_leave_type('${TENANT}', 'sick', 'Sick', 'days', true, false, auto_approve => true) ->> 'id')::uuid;
  perform better_supabase.accrue_leave('${TENANT}', v_holiday, 10, 2099);
  perform better_supabase.request_leave('${TENANT}', v_sick, '2099-03-02', '2099-03-02', 'afternoon', employee_id => '${ALICE_EMPLOYEE}', fields => '{"reason": "dentist"}');
  perform better_supabase.request_leave('${TENANT}', v_sick, '2099-03-03', '2099-03-03', employee_id => '${BOB_EMPLOYEE}');
  ${AS(ALICE)}
  v_link := better_supabase.create_share_link('${TENANT}', 'leave_team_feed', '88888888-8888-4888-8888-888888888888', 'view');
  v_feed := better_supabase.leave_feed(v_link ->> 'token');
  if v_feed ->> 'teamId' <> '88888888-8888-4888-8888-888888888888'
    or jsonb_array_length(v_feed -> 'requests') <> 1
    or v_feed -> 'requests' -> 0 ->> 'name' <> 'Alice'
    or v_feed -> 'requests' -> 0 ->> 'type' is not null
    or v_feed -> 'requests' -> 0 ->> 'startPart' <> 'afternoon'
    or v_feed -> 'requests' -> 0 -> 'fields' ->> 'reason' <> 'dentist' then
    raise exception 'team feed %', v_feed;
  end if;
end;
$$;`,
      ],
    });

    expect(stack.url).not.toBe("");
  });

  it("dates adjustments and accruals on an effective day", async () => {
    await expect(
      runEmployees(
        `create table public.denied (user_id uuid, permission text);
insert into public.denied values ('${BOB}', 'leave.manage');
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select not exists (select 1 from public.denied d where d.user_id = auth.uid() and d.permission = can.permission) $$;
do $$
declare
  v_type uuid;
  v_entry jsonb;
begin
  ${SERVICE}
  v_type := (better_supabase.save_leave_type('${TENANT}', 'vacation', 'Vacation', 'hours') ->> 'id')::uuid;
  v_entry := better_supabase.adjust_leave_balance('${TENANT}', null, v_type, -4, null, 'adjustment', 'correction',
    employee_id => '${ALICE_EMPLOYEE}', effective_on => '2098-11-15');
  if (select effective_on from public.time_off_ledger where id = (v_entry ->> 'id')::uuid) <> '2098-11-15'
    or (v_entry ->> 'period')::integer <> 2098 then
    raise exception 'adjusted %', v_entry;
  end if;
  if better_supabase.accrue_leave('${TENANT}', v_type, 8, null, employee_ids => array['${ALICE_EMPLOYEE}'::uuid, '${NO_ACCOUNT}'::uuid],
    effective_on => '2099-05-01') <> 2 then
    raise exception 'accrued';
  end if;
  if (select count(*) from public.time_off_ledger where kind = 'accrual' and effective_on = '2099-05-01') <> 2 then
    raise exception 'accrual dates %', (select jsonb_agg(row_to_json(l)) from public.time_off_ledger l);
  end if;
  perform better_supabase.accrue_leave('${TENANT}', v_type, 8, 2099, employee_ids => array['${ALICE_EMPLOYEE}'::uuid]);
  if not exists (select 1 from public.time_off_ledger where kind = 'accrual' and effective_on = '2099-01-01') then
    raise exception 'default effective day';
  end if;
  ${AS(BOB)}
  begin
    perform better_supabase.adjust_leave_balance('${TENANT}', null, v_type, 1, null, employee_id => '${ALICE_EMPLOYEE}', effective_on => '2099-01-01');
    raise exception 'allowed a backdated adjustment';
  exception when others then
    if sqlerrm not like '%not allowed%' then
      raise;
    end if;
  end;
  begin
    perform better_supabase.accrue_leave('${TENANT}', v_type, 1, effective_on => '2099-01-01');
    raise exception 'allowed a dated accrual';
  exception when others then
    if sqlerrm not like '%not allowed%' then
      raise;
    end if;
  end;
end;
$$;`,
        EMPLOYEE_BLOCKS,
        EMPLOYEE_OWN,
        EMPLOYEE_APP,
      ),
    ).resolves.toBeUndefined();

    const leave = EMPLOYEE_BLOCKS["leave"];

    const sql = renderBlocks(["employees", "leave"], {
      modules: {
        leave: {
          ...leave,
          columns: {
            ...leave?.columns,
            balances: { ...leave?.columns?.["balances"], effectiveOn: null },
          },
        },
      },
      ownTables: EMPLOYEE_OWN,
    })
      .map((file) => file.contents)
      .join("\n");

    const body = (name: string): string => {
      const start = sql.indexOf(`function "better_supabase"."${name}"(`);

      return sql.slice(start, sql.indexOf("$$;", start));
    };

    expect(body("adjust_leave_balance")).toContain(
      "LEAVE_EFFECTIVE_UNSUPPORTED",
    );
    expect(body("accrue_leave")).toContain("LEAVE_EFFECTIVE_UNSUPPORTED");
  });

  it("shares a team by an employees column, with names and confidential leave as busy", async () => {
    const reader = "99999999-9999-4999-8999-999999999999";
    const team = "88888888-8888-4888-8888-888888888888";
    const leave = EMPLOYEE_BLOCKS["leave"];

    const files = renderBlocks(["employees", "teams", "leave", "share-links"], {
      modules: {
        employees: {
          options: { extraColumns: { department_team_id: "uuid" } },
        },
        leave: {
          ...leave,
          columns: {
            ...leave?.columns,
            types: {
              ...leave?.columns?.["types"],
              confidential: "confidential",
            },
          },
          options: {
            ...leave?.options,
            feed: {
              teams: true,
              names: true,
              teamColumn: "department_team_id",
              teamName: true,
              organizationName: "public.orgs.name",
              confidential: "busy",
            },
          },
        },
      },
      ownTables: EMPLOYEE_OWN,
    });

    await using stack = await liteStack({
      driver: "pglite",
      migrations: [
        ROLES,
        `${EMPLOYEE_APP.replace(
          "  deducts_balance boolean not null default true,",
          "  deducts_balance boolean not null default true,\n  confidential boolean not null default false,",
        )}
create table public.orgs (id uuid primary key, name text not null);
create schema if not exists extensions;
create or replace function extensions.gen_random_bytes(n integer) returns bytea
language sql volatile as $$ select decode(md5(random()::text) || md5(random()::text), 'hex') $$;
create or replace function extensions.digest(data bytea, type text) returns bytea
language sql immutable as $$ select sha256(data) $$;`,
        ...files
          .filter((file) => file.kind !== "data")
          .map((file) => file.contents),
      ],
      seed: [
        ...files
          .filter((file) => file.kind === "data")
          .map((file) => file.contents),
        ALLOW,
        STAFF,
        `insert into public.orgs values ('${TENANT}', 'Acme');
insert into better_supabase.teams (id, tenant_id, name, slug) values ('${team}', '${TENANT}', 'Support', 'support');
update better_supabase.employees set department_team_id = '${team}' where id in ('${ALICE_EMPLOYEE}', '${NO_ACCOUNT}');
create table public.denied (user_id uuid, permission text);
insert into public.denied values ('${reader}', 'leave.manage');
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select not exists (select 1 from public.denied d where d.user_id = auth.uid() and d.permission = can.permission) $$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select not exists (select 1 from public.denied d where d.user_id = can_user.member and d.permission = can_user.permission) $$;
insert into auth.users (id) values ('${reader}');
insert into better_supabase.memberships (organization_id, user_id, role) values ('${TENANT}', '${reader}', 'member');`,
        `do $$
declare
  v_holiday uuid;
  v_sick uuid;
  v_feed jsonb;
begin
  ${SERVICE}
  v_holiday := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday', 'days') ->> 'id')::uuid;
  v_sick := (better_supabase.save_leave_type('${TENANT}', 'sick', 'Sick', 'days', true, false) ->> 'id')::uuid;
  update public.time_off_types set confidential = true where id = v_sick;
  perform better_supabase.adjust_leave_balance('${TENANT}', null, v_holiday, 10, 2099, 'grant', null, employee_id => '${ALICE_EMPLOYEE}');
  perform better_supabase.adjust_leave_balance('${TENANT}', null, v_holiday, 10, 2099, 'grant', null, employee_id => '${BOB_EMPLOYEE}');
  perform better_supabase.decide_leave_request((better_supabase.request_leave('${TENANT}', v_holiday, '2099-03-02', '2099-03-02', employee_id => '${ALICE_EMPLOYEE}') ->> 'id')::uuid, true, null);
  perform better_supabase.decide_leave_request((better_supabase.request_leave('${TENANT}', v_sick, '2099-03-05', '2099-03-05', employee_id => '${NO_ACCOUNT}') ->> 'id')::uuid, true, null);
  perform better_supabase.decide_leave_request((better_supabase.request_leave('${TENANT}', v_holiday, '2099-03-09', '2099-03-09', employee_id => '${BOB_EMPLOYEE}') ->> 'id')::uuid, true, null);
  ${AS(reader)}
  v_feed := better_supabase.leave_feed(better_supabase.create_share_link('${TENANT}', 'leave_team_feed', '${team}', 'view') ->> 'token');
  if v_feed ->> 'organizationName' <> 'Acme' or v_feed ->> 'teamName' <> 'Support'
    or jsonb_array_length(v_feed -> 'requests') <> 1 or v_feed -> 'requests' -> 0 ->> 'name' <> 'Alice'
    or jsonb_array_length(v_feed -> 'busy') <> 1 or v_feed -> 'busy' -> 0 ->> 'name' <> 'Dana'
    or v_feed -> 'busy' -> 0 ? 'typeId' or v_feed -> 'busy' -> 0 ? 'type' or v_feed -> 'busy' -> 0 ? 'amount' then
    raise exception 'reader feed %', v_feed;
  end if;
  ${AS(ALICE)}
  v_feed := better_supabase.leave_feed(better_supabase.create_share_link('${TENANT}', 'leave_team_feed', '${team}', 'view') ->> 'token');
  if jsonb_array_length(v_feed -> 'requests') <> 2 or jsonb_array_length(v_feed -> 'busy') <> 0 then
    raise exception 'holder feed %', v_feed;
  end if;
end;
$$;`,
      ],
    });

    expect(stack.url).not.toBe("");
    expect(() =>
      renderBlocks(["employees", "teams", "leave", "share-links"], {
        modules: { leave: { options: { feed: { teamColumn: "team_id" } } } },
      }),
    ).toThrow(/teamColumn/);
    expect(() =>
      renderBlocks(["employees", "teams", "leave", "share-links"], {
        modules: { leave: { options: { feed: { confidential: "busy" } } } },
      }),
    ).toThrow(/confidential/);
  });

  it("keys the ledger by employee on the block's own tables", async () => {
    await expect(
      runEmployees(
        `do $$
declare
  v_type uuid;
  v_id uuid;
  v_balances jsonb;
begin
  ${SERVICE}
  v_type := (better_supabase.save_leave_type('${TENANT}', 'vacation', 'Vacation') ->> 'id')::uuid;
  if better_supabase.accrue_leave('${TENANT}', v_type, 10, 2099) <> 3 then
    raise exception 'accrued';
  end if;
  ${AS(BOB)}
  v_id := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03', employee_id => '${NO_ACCOUNT}') ->> 'id')::uuid;
  ${SERVICE}
  perform better_supabase.approve_leave_request(v_id);
  ${AS(BOB)}
  v_balances := better_supabase.leave_balances('${TENANT}', null, 2099, employee_id => '${NO_ACCOUNT}');
  if (v_balances -> 0 ->> 'available')::numeric <> 8 or v_balances -> 0 ->> 'userId' is not null then
    raise exception 'balances %', v_balances;
  end if;
end;
$$;`,
        { employees: {}, leave: { options: { owner: "employee" } } },
        {},
        "",
      ),
    ).resolves.toBeUndefined();
  });
});
