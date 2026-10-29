import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";
import type { BlockSqlAccessProvider } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ADMIN = "22222222-2222-4222-8222-222222222222";
const REQUESTER = "33333333-3333-4333-8333-333333333333";
const ANN = "44444444-4444-4444-8444-444444444444";
const BEN = "55555555-5555-4555-8555-555555555555";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const AUTHZ = `
create schema if not exists authz;
create table authz.grants (user_id uuid not null, tenant uuid, permission text not null);
create function authz.ids_with(permission text) returns setof uuid
  language sql stable as $$
    select g.tenant from authz.grants g where g.user_id = auth.uid() and g.permission = ids_with.permission and g.tenant is not null
  $$;
create function authz.is_platform(permission text) returns boolean
  language sql stable as $$
    select exists (select 1 from authz.grants g where g.user_id = auth.uid() and g.permission = is_platform.permission and g.tenant is null)
  $$;
create function authz.holders_of(permission text, tenant uuid) returns setof uuid
  language sql stable as $$
    select g.user_id from authz.grants g where g.permission = holders_of.permission and g.tenant = holders_of.tenant
  $$;
grant usage on schema authz to authenticated;
`;

const GRANTS = `
insert into authz.grants values
  ('${ADMIN}', '${TENANT}', 'approvals.manage'),
  ('${ADMIN}', '${TENANT}', 'approvals.request'),
  ('${ADMIN}', '${TENANT}', 'approvals.read'),
  ('${REQUESTER}', '${TENANT}', 'workflow.manage');
`;

const PROVIDER: BlockSqlAccessProvider = {
  name: "test",
  scope: "organization",
  idType: "uuid",
  functions: {
    idsWith: "authz.ids_with({permission})",
    isPlatform: "authz.is_platform({permission})",
    holdersOf: "authz.holders_of({permission}, {tenant})",
  },
};

const BLOCKS: AnyBlocksConfig = {
  permissions: { model: "provider" },
  approvals: {
    options: {
      tenantPolicies: true,
      conditions: "payload",
      policyExtraColumns: { description: "text" },
      policies: {
        invoice: { send: { steps: [{ approvers: { users: [ANN] } }] } },
        "*": {
          "quote.send": { steps: [{ approvers: { users: [BEN] } }] },
          "access.member.role.update": { steps: [], effects: ["access"] },
        },
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"role":"authenticated","sub":"${user}"}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);`;

const BOOT = { timeout: 60_000 };

const render = (modules: AnyBlocksConfig): string =>
  renderBlocks(["permissions", "approvals"], {
    modules,
    accessProvider: PROVIDER,
  })
    .filter((file) => file.module === "approvals")
    .map((file) => file.contents)
    .join("\n");

async function run(
  check: string,
  names: readonly string[] = ["permissions", "approvals"],
): Promise<void> {
  const files = renderBlocks(names, {
    modules: BLOCKS,
    accessProvider: PROVIDER,
  });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      AUTHZ,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      GRANTS,
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

const ownPolicy = (users: readonly string[], extra = ""): string =>
  `jsonb_build_object('steps', jsonb_build_array(jsonb_build_object('approvers', jsonb_build_object('users', jsonb_build_array(${users.map((user) => `'${user}'`).join(", ")})), 'required', ${String(users.length)}))${extra})`;

describe("requests under the app's own policy", BOOT, () => {
  it("files a workflow request for a named requester, who can't approve it", async () => {
    await expect(
      run(`do $$
declare
  v_req jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_req := better_supabase.request_approval('${TENANT}', 'workflow_run', 'run-1', 'approval',
    policy => ${ownPolicy([REQUESTER, ANN], ", 'expiresIn', 'P2D', 'mode', 'authorize'")}, requested_by => '${REQUESTER}');
  v_id := (v_req ->> 'id')::uuid;
  if v_req ->> 'requestedBy' <> '${REQUESTER}' or v_req ->> 'expiresAt' is null
    or jsonb_array_length(v_req -> 'steps') <> 1 or v_req ->> 'mode' <> 'authorize' then
    raise exception 'filed %', v_req;
  end if;
  ${as(REQUESTER)}
  if better_supabase.approval_eligible(v_id) then
    raise exception 'the requester may approve their own workflow request';
  end if;
  begin
    perform better_supabase.decide_approval(v_id, 'approved');
    raise exception 'the requester approved';
  exception when others then
    if sqlerrm not like '%not an approver%' then
      raise;
    end if;
  end;
  ${SERVICE}
  begin
    perform better_supabase.decide_approval(v_id, 'approved', null, '${REQUESTER}');
    raise exception 'the service role approved for the requester';
  exception when others then
    if sqlerrm not like '%can''t decide their own request%' then
      raise;
    end if;
  end;
  ${as(ANN)}
  if better_supabase.decide_approval(v_id, 'approved') ->> 'status' <> 'pending' then
    raise exception 'one of two finished it';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("only tightens a floor, and stands alone without one", async () => {
    await expect(
      run(`do $$
declare
  v_req jsonb;
begin
  ${SERVICE}
  v_req := better_supabase.request_approval('${TENANT}', 'invoice', 'i-1', 'send',
    policy => '{"mode": "confirm", "steps": [], "selfApproval": true}'::jsonb, requested_by => '${REQUESTER}');
  if v_req ->> 'mode' <> 'authorize' or jsonb_array_length(v_req -> 'steps') <> 1
    or v_req -> 'steps' -> 0 -> 'approvers' -> 'users' ->> 0 <> '${ANN}'
    or (select (policy ->> 'selfApproval')::boolean from better_supabase.approval_requests where id = (v_req ->> 'id')::uuid) then
    raise exception 'loosened the floor %', v_req;
  end if;
  v_req := better_supabase.request_approval('${TENANT}', 'invoice', 'i-2', 'send', policy => ${ownPolicy([BEN])});
  if jsonb_array_length(v_req -> 'steps') <> 2 or v_req -> 'steps' -> 1 -> 'approvers' -> 'users' ->> 0 <> '${BEN}' then
    raise exception 'added no step %', v_req;
  end if;
  v_req := better_supabase.request_approval('${TENANT}', 'workflow_run', 'run-2', 'confirm',
    policy => '{"mode": "confirm", "steps": []}'::jsonb, requested_by => '${REQUESTER}');
  ${as(REQUESTER)}
  if better_supabase.decide_approval((v_req ->> 'id')::uuid, 'approved') ->> 'status' <> 'approved' then
    raise exception 'the requester could not confirm';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a policy or another requester from a signed-in caller, and a bad policy", async () => {
    await expect(
      run(`do $$
begin
  ${as(ADMIN)}
  perform better_supabase.request_approval('${TENANT}', 'invoice', 'i-1', 'send', policy => '{"mode": "confirm", "steps": []}'::jsonb);
end;
$$;`),
    ).rejects.toThrow(
      /only the service role files a request under its own policy/,
    );
    await expect(
      run(`do $$
begin
  ${as(ADMIN)}
  perform better_supabase.request_approval('${TENANT}', 'invoice', 'i-1', 'send', requested_by => '${REQUESTER}');
end;
$$;`),
    ).rejects.toThrow(/only the service role files a request for another user/);
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.request_approval('${TENANT}', 'workflow_run', 'run-1', 'approval',
    policy => '{"steps": [{"approvers": {}}]}'::jsonb);
end;
$$;`),
    ).rejects.toThrow(/policy must be/);
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.request_approval('${TENANT}', 'workflow_run', 'run-1', 'approval',
    policy => '{"steps": [], "expiresIn": "soon"}'::jsonb);
end;
$$;`),
    ).rejects.toThrow(/policy must be/);
  });
});

describe("floors for dotted actions and every subject type", BOOT, () => {
  it("matches a * floor for any subject type, and a tenant policy tightens it", async () => {
    await expect(
      run(`do $$
declare
  v_need jsonb;
begin
  ${SERVICE}
  v_need := better_supabase.approval_requirement('${TENANT}', 'chat_thread', 'quote.send', '{}'::jsonb);
  if v_need -> 'steps' -> 0 -> 'approvers' -> 'users' ->> 0 <> '${BEN}' then
    raise exception 'chat thread %', v_need;
  end if;
  if better_supabase.approval_requirement('${TENANT}', 'mcp_client', 'quote.send', '{}'::jsonb) is null then
    raise exception 'mcp client';
  end if;
  if better_supabase.approval_requirement('${TENANT}', 'invoice', 'send', '{}'::jsonb) -> 'steps' -> 0 -> 'approvers' -> 'users' ->> 0 <> '${ANN}' then
    raise exception 'the exact floor lost to the * floor';
  end if;
  if better_supabase.approval_requirement('${TENANT}', 'chat_thread', 'quote.void', '{}'::jsonb) is not null then
    raise exception 'an unlisted action needs approval';
  end if;
  ${as(ADMIN)}
  perform better_supabase.save_approval_policy('${TENANT}', jsonb_build_object('subjectType', 'workflow_run', 'action', 'quote.send',
    'name', 'Second look', 'steps', jsonb_build_array(jsonb_build_object('approvers', jsonb_build_object('users', jsonb_build_array('${ANN}'))))));
  perform better_supabase.save_approval_policy('${TENANT}', jsonb_build_object('subjectType', '*', 'action', '*', 'effect', 'access',
    'name', 'Access changes', 'mode', 'confirm', 'steps', '[]'::jsonb));
  ${SERVICE}
  if jsonb_array_length(better_supabase.approval_requirement('${TENANT}', 'workflow_run', 'quote.send', '{}'::jsonb) -> 'steps') <> 2 then
    raise exception 'tenant policy on a * floor';
  end if;
  if better_supabase.approval_requirement('${TENANT}', 'member', 'access.member.role.update', '{}'::jsonb) ->> 'mode' <> 'confirm' then
    raise exception 'effect on a * floor';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a malformed action and keeps exact floors without a * floor", () => {
    expect(() =>
      render({
        approvals: {
          options: { policies: { invoice: { "quote..send": { steps: [] } } } },
        },
      }),
    ).toThrow(/has an invalid name/);
    expect(() =>
      render({
        approvals: { options: { policies: { "+": { send: { steps: [] } } } } },
      }),
    ).toThrow(/has an invalid name/);

    const sql = render({
      approvals: {
        options: {
          tenantPolicies: true,
          policies: { invoice: { send: { steps: [] } } },
        },
      },
    });

    expect(sql).toContain("f.value ->> 'subjectType' = v_type");
    expect(sql).not.toContain("'*:' || approval_policy.action");
  });
});

describe("policy columns and notifications", BOOT, () => {
  it("saves and reads a policy's extra columns", async () => {
    await expect(
      run(`do $$
declare
  v_policy jsonb;
begin
  ${as(ADMIN)}
  v_policy := better_supabase.save_approval_policy('${TENANT}', jsonb_build_object('subjectType', 'invoice', 'action', 'send',
    'name', 'Big invoices', 'steps', '[]'::jsonb, 'fields', jsonb_build_object('description', 'Over the limit')));
  if v_policy -> 'fields' ->> 'description' <> 'Over the limit' then
    raise exception 'saved %', v_policy;
  end if;
  v_policy := better_supabase.save_approval_policy('${TENANT}', jsonb_build_object('id', v_policy ->> 'id', 'name', 'Large invoices'));
  if v_policy -> 'fields' ->> 'description' <> 'Over the limit' or v_policy ->> 'name' <> 'Large invoices' then
    raise exception 'kept %', v_policy;
  end if;
  if better_supabase.list_approval_policies('${TENANT}') -> 0 -> 'fields' ->> 'description' <> 'Over the limit' then
    raise exception 'listed %', better_supabase.list_approval_policies('${TENANT}');
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("needs tenant policies for policy columns", () => {
    expect(() =>
      render({
        approvals: {
          options: {
            policyExtraColumns: { description: "text" },
            policies: {
              invoice: { send: { steps: [{ approvers: { role: "a" } }] } },
            },
          },
        },
      }),
    ).toThrow(
      /policyExtraColumns needs blocks.approvals.options.tenantPolicies/,
    );
  });

  it("switches the block's notifications off, and enriches them through a hook", () => {
    const notify = (options: Readonly<Record<string, unknown>>): string =>
      renderBlocks(["permissions", "notifications", "approvals"], {
        modules: {
          approvals: {
            options: {
              ...options,
              policies: {
                invoice: { send: { steps: [{ approvers: { role: "a" } }] } },
              },
            },
          },
        },
      })
        .filter((file) => file.module === "approvals")
        .map((file) => file.contents)
        .join("\n");

    const on = notify({});

    const off = notify({ notifications: false });

    expect(on).toContain(`"approval_notification"(uuid, text, jsonb)`);
    expect(on).toMatch(/perform "?better_supabase"?\."?notify"?\(v_note\)/);
    expect(off).not.toContain("notify(v_note)");
    expect(off).not.toContain(`"approval_notification"(uuid, text, jsonb)`);
  });

  it("merges what the app's hook returns into a notification, and skips one it nulls", async () => {
    await expect(
      run(
        `create or replace function public.approval_notification(request_id uuid, kind text, notification jsonb)
returns jsonb language sql as $$
  select case when notification ->> 'subject_id' = 'quiet' then null
    else jsonb_build_object('action_path', '/quotes/' || (notification ->> 'subject_id'), 'priority', 'high', 'data', jsonb_build_object('risk', 'high')) end
$$;
insert into auth.users (id) values ('${ANN}'), ('${BEN}') on conflict do nothing;
do $$
declare
  v_event record;
begin
  ${SERVICE}
  perform better_supabase.request_approval('${TENANT}', 'invoice', 'loud', 'send');
  perform better_supabase.request_approval('${TENANT}', 'invoice', 'quiet', 'send');
  select * into v_event from better_supabase.notification_events where subject_id = 'loud';
  if v_event.action_path <> '/quotes/loud' or v_event.priority <> 'high'
    or v_event.data ->> 'risk' <> 'high' or v_event.data ->> 'action' <> 'send' then
    raise exception 'enriched %', row_to_json(v_event);
  end if;
  if exists (select 1 from better_supabase.notification_events where subject_id = 'quiet') then
    raise exception 'a nulled notification was sent';
  end if;
end;
$$;`,
        ["permissions", "notifications", "approvals"],
      ),
    ).resolves.toBeUndefined();
  });
});
