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
const STAFF = "66666666-6666-4666-8666-666666666666";
const OWNER = "77777777-7777-4777-8777-777777777777";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// Grants an authorization provider keeps: a null tenant is a platform grant.
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
  ('${ANN}', '${TENANT}', 'invoices.approve'),
  ('${BEN}', '${TENANT}', 'invoices.approve'),
  ('${ADMIN}', '${TENANT}', 'approvals.manage'),
  ('${ADMIN}', '${TENANT}', 'approvals.request'),
  ('${STAFF}', null, 'approvals.manage'),
  ('${STAFF}', null, 'approvals.read'),
  ('${STAFF}', null, 'approvals.escalation'),
  ('${OWNER}', null, 'platform.approvalPolicy.manage');
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

const MONEY = { steps: [], effects: ["money-movement"] };

const BLOCKS: AnyBlocksConfig = {
  permissions: { model: "provider" },
  approvals: {
    options: {
      tenantPolicies: true,
      platformPolicies: true,
      conditions: "payload",
      tenantless: ["ai_chat"],
      policies: {
        invoice: {
          refund: MONEY,
          send: {
            steps: [
              {
                approvers: { permission: "invoices.approve" },
                required: "all",
              },
            ],
          },
        },
        ai_tool: { "*": MONEY },
        ai_chat: {
          run: {
            steps: [
              {
                approvers: { users: [ADMIN] },
                escalateAfter: "PT1H",
                escalateTo: { permission: "approvals.escalation" },
              },
            ],
          },
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

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(
  check: string,
  modules: AnyBlocksConfig = BLOCKS,
): Promise<void> {
  const files = renderBlocks(["permissions", "approvals"], {
    modules,
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

const condition = (amount: number): string =>
  JSON.stringify({
    id: "root",
    type: "group",
    combinator: "and",
    rules: [
      {
        id: "a",
        type: "rule",
        path: ["amount"],
        operator: "gt",
        value: amount,
      },
      {
        id: "k",
        type: "rule",
        path: ["actorKind"],
        operator: "is_any_of",
        value: ["agent", "mcp"],
      },
    ],
  });

describe(
  "approval policies by effect, catch-all and platform rows",
  BOOT,
  () => {
    it("matches effects, any action, platform floors and payload conditions", async () => {
      await expect(
        run(`do $$
declare
  v_need jsonb;
begin
  ${as(STAFF)}
  perform better_supabase.save_approval_policy(null, jsonb_build_object('subjectType', '*', 'action', '*', 'effect', 'money-movement',
    'name', 'Money moves', 'steps', jsonb_build_array(jsonb_build_object('approvers', jsonb_build_object('users', jsonb_build_array('${ADMIN}'))))));
  perform better_supabase.save_approval_policy(null, jsonb_build_object('subjectType', 'report', 'action', 'export',
    'name', 'Exports', 'mode', 'confirm', 'steps', '[]'::jsonb));
  if jsonb_array_length(better_supabase.list_approval_policies(null)) <> 2 then
    raise exception 'platform policies %', better_supabase.list_approval_policies(null);
  end if;

  ${SERVICE}
  v_need := better_supabase.approval_requirement('${TENANT}', 'ai_tool', 'pay_out', '{}'::jsonb);
  if v_need is null or v_need -> 'steps' -> 0 -> 'approvers' -> 'users' ->> 0 <> '${ADMIN}' or v_need -> 'effects' ->> 0 <> 'money-movement' then
    raise exception 'the catch-all floor with an effect %', v_need;
  end if;
  if better_supabase.approval_requirement('${TENANT}', 'invoice', 'export', '{}'::jsonb) is not null then
    raise exception 'an action without a floor needs nothing';
  end if;
  v_need := better_supabase.approval_requirement('${TENANT}', 'report', 'export', '{}'::jsonb);
  if v_need ->> 'mode' <> 'confirm' then
    raise exception 'a platform policy stands in for a floor %', v_need;
  end if;

  ${as(ADMIN)}
  perform better_supabase.save_approval_policy('${TENANT}', jsonb_build_object('subjectType', 'invoice', 'action', 'refund',
    'name', 'Large agent refunds', 'conditions', '${condition(100)}'::jsonb,
    'steps', jsonb_build_array(jsonb_build_object('approvers', jsonb_build_object('users', jsonb_build_array('${ANN}'))))));
  perform better_supabase.save_approval_policy('${TENANT}', jsonb_build_object('subjectType', 'report', 'action', 'export',
    'name', 'Exports here', 'steps', '[]'::jsonb));
  if jsonb_array_length(better_supabase.approval_requirement('${TENANT}', 'invoice', 'refund', '{"amount": 50, "actorKind": "agent"}'::jsonb) -> 'steps') <> 1
    or jsonb_array_length(better_supabase.approval_requirement('${TENANT}', 'invoice', 'refund', '{"amount": 500, "actorKind": "human"}'::jsonb) -> 'steps') <> 1
    or jsonb_array_length(better_supabase.approval_requirement('${TENANT}', 'invoice', 'refund', '{"amount": 500, "actorKind": "agent"}'::jsonb) -> 'steps') <> 2 then
    raise exception 'payload conditions';
  end if;
end;
$$;`),
      ).resolves.toBeUndefined();
    });

    it("refuses a tenant policy without a floor, a platform policy by a member and a bad operator", async () => {
      const save = (
        user: string,
        tenant: string,
        policy: string,
      ): Promise<void> =>
        run(`do $$
begin
  ${as(user)}
  perform better_supabase.save_approval_policy(${tenant}, '${policy}'::jsonb);
end;
$$;`);

      await expect(
        save(
          ADMIN,
          `'${TENANT}'`,
          '{"subjectType":"report","action":"export","name":"x","steps":[]}',
        ),
      ).rejects.toThrow(
        /there is none for this subject type, action and effect/,
      );
      await expect(
        save(
          ADMIN,
          "null",
          '{"subjectType":"*","action":"*","name":"x","steps":[]}',
        ),
      ).rejects.toThrow(/needs approvals.manage/);
      await expect(
        save(
          ADMIN,
          `'${TENANT}'`,
          '{"subjectType":"invoice","action":"refund","name":"x","steps":[],"conditions":{"type":"group","combinator":"and","rules":[{"type":"rule","path":["a"],"operator":"near","value":1}]}}',
        ),
      ).rejects.toThrow(/conditions must be a filter tree/);
      await expect(
        save(
          ADMIN,
          `'${TENANT}'`,
          '{"subjectType":"invoice","action":"refund","name":"x","effect":"payroll","steps":[]}',
        ),
      ).rejects.toThrow(
        /there is none for this subject type, action and effect/,
      );
    });
  },
);

describe("platform policies under their own key", BOOT, () => {
  const PLATFORM_KEY: AnyBlocksConfig = {
    ...BLOCKS,
    approvals: {
      ...BLOCKS["approvals"],
      permissions: { platform: "platform.approvalPolicy.manage" },
    },
  };

  const save = (user: string, tenant = "null"): string => `do $$
begin
  ${as(user)}
  perform better_supabase.save_approval_policy(${tenant}, jsonb_build_object('subjectType', 'report', 'action', 'export',
    'name', 'Exports', 'mode', 'confirm', 'steps', '[]'::jsonb));
  if jsonb_array_length(better_supabase.list_approval_policies(null)) <> 1 then
    raise exception 'platform policies %', better_supabase.list_approval_policies(null);
  end if;
end;
$$;`;

  it("lets a holder of the platform key save and list platform policies", async () => {
    await expect(run(save(OWNER), PLATFORM_KEY)).resolves.toBeUndefined();
  });

  it("refuses platform staff with only approvals.manage and an organization manager", async () => {
    await expect(run(save(STAFF), PLATFORM_KEY)).rejects.toThrow(
      /needs approvals.manage/,
    );
    await expect(run(save(ADMIN), PLATFORM_KEY)).rejects.toThrow(
      /needs approvals.manage/,
    );
    await expect(
      run(
        `do $$
begin
  ${as(STAFF)}
  perform better_supabase.list_approval_policies(null);
end;
$$;`,
        PLATFORM_KEY,
      ),
    ).rejects.toThrow(/needs approvals.read/);
  });

  it("keeps approvals.manage for platform policies by default", async () => {
    await expect(run(save(OWNER))).rejects.toThrow(/needs approvals.manage/);
  });
});

describe(
  "approvers, escalation, deciders and tenantless requests",
  BOOT,
  () => {
    it("asks every holder, lets the service role decide for a user and escalates", async () => {
      await expect(
        run(`do $$
declare
  v_req jsonb;
  v_id uuid;
  v_chat uuid;
begin
  ${SERVICE}
  v_req := better_supabase.request_approval('${TENANT}', 'invoice', 'i-1', 'send');
  v_id := (v_req ->> 'id')::uuid;
  if (v_req -> 'steps' -> 0 ->> 'required')::integer <> 2
    or not (v_req -> 'steps' -> 0 -> 'approvers' -> 'users') @> jsonb_build_array('${ANN}', '${BEN}') then
    raise exception 'every holder %', v_req;
  end if;
  ${as(ANN)}
  if better_supabase.decide_approval(v_id, 'approved') ->> 'status' <> 'pending' then
    raise exception 'one holder finished it';
  end if;
  ${SERVICE}
  v_req := better_supabase.decide_approval(v_id, 'approved', null, '${BEN}');
  if v_req ->> 'status' <> 'approved'
    or (select approver from better_supabase.approval_decisions where request_id = v_id and approver = '${BEN}') is null then
    raise exception 'decided for Ben %', v_req;
  end if;

  ${as(REQUESTER)}
  v_chat := (better_supabase.request_approval(null, 'ai_chat', 'chat-1', 'run') ->> 'id')::uuid;
  if (select tenant_id from better_supabase.approval_requests where id = v_chat) is not null
    or jsonb_array_length(better_supabase.list_approvals(null)) <> 1 then
    raise exception 'a tenantless request %', better_supabase.list_approvals(null);
  end if;
  ${as(STAFF)}
  if better_supabase.approval_eligible(v_chat) then
    raise exception 'the fallback decides before the escalation';
  end if;
  ${SERVICE}
  update better_supabase.approval_requests set created_at = now() - interval '2 hours' where id = v_chat;
  if better_supabase.escalate_approvals() <> 1 or better_supabase.escalate_approvals() <> 0 then
    raise exception 'escalated once';
  end if;
  ${as(STAFF)}
  if better_supabase.decide_approval(v_chat, 'approved') ->> 'status' <> 'approved' then
    raise exception 'the fallback could not decide';
  end if;
end;
$$;`),
      ).resolves.toBeUndefined();
    });

    it("refuses a decision for someone else, a tenantless type it doesn't list and the requester as decider", async () => {
      await expect(
        run(`do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.request_approval('${TENANT}', 'invoice', 'i-1', 'send') ->> 'id')::uuid;
  ${as(ANN)}
  perform better_supabase.decide_approval(v_id, 'approved', null, '${BEN}');
end;
$$;`),
      ).rejects.toThrow(/only the service role decides for another user/);
      await expect(
        run(`do $$
begin
  ${as(REQUESTER)}
  perform better_supabase.request_approval(null, 'invoice', 'i-1', 'send');
end;
$$;`),
      ).rejects.toThrow(/needs an organization/);
      await expect(
        run(`do $$
declare
  v_id uuid;
begin
  ${as(REQUESTER)}
  v_id := (better_supabase.request_approval(null, 'ai_chat', 'chat-1', 'run') ->> 'id')::uuid;
  ${SERVICE}
  perform better_supabase.decide_approval(v_id, 'approved', null, '${REQUESTER}');
end;
$$;`),
      ).rejects.toThrow(/can't decide their own request/);
    });

    it("keeps the defaults: no tenantless requests and no platform policies", () => {
      const sql = renderBlocks(["approvals"], {
        modules: {
          approvals: {
            options: {
              tenantPolicies: true,
              policies: { invoice: { send: { steps: [] } } },
            },
          },
        },
      })
        .filter((file) => file.module === "approvals")
        .map((file) => file.contents)
        .join("\n");

      expect(sql).toContain('"tenant_id" uuid not null');
      expect(sql).not.toContain("drop not null");
      expect(sql).not.toContain("APPROVAL_TENANT_REQUIRED");
      expect(sql).not.toContain("approval_condition(");
      expect(sql).toContain("APPROVAL_CONDITIONS_UNSUPPORTED");
    });

    it("refuses platform policies without tenant policies and a bad escalation", () => {
      expect(() =>
        renderBlocks(["approvals"], {
          modules: {
            approvals: {
              options: {
                platformPolicies: true,
                policies: {
                  invoice: { send: { steps: [{ approvers: { role: "a" } }] } },
                },
              },
            },
          },
        }),
      ).toThrow(/needs blocks.approvals.options.tenantPolicies/);
      expect(() =>
        renderBlocks(["approvals"], {
          modules: {
            approvals: {
              options: {
                policies: {
                  invoice: {
                    send: {
                      steps: [
                        { approvers: { role: "a" }, escalateAfter: "soon" },
                      ],
                    },
                  },
                },
              },
            },
          },
        }),
      ).toThrow(/escalateAfter/);
    });
  },
);
