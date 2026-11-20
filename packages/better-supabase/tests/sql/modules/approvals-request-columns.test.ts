import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const ALICE_EMPLOYEE = "44444444-4444-4444-8444-444444444444";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const ADDED = `
alter table better_supabase.approval_requests add column source text not null default 'app';
alter table better_supabase.approval_requests add column employee_id uuid;
`;

const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}') on conflict do nothing;
insert into better_supabase.memberships (organization_id, user_id, role)
  values ('${TENANT}', '${ALICE}', 'member') on conflict do nothing;
insert into better_supabase.employees (id, tenant_id, user_id, name)
  values ('${ALICE_EMPLOYEE}', '${TENANT}', '${ALICE}', 'Alice');
`;

const AS_ALICE = `perform set_config('request.jwt.claims', '{"sub":"${ALICE}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${ALICE}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const LAYOUT = {
  appColumns: {
    "better_supabase.approval_requests": [
      { name: "source", type: "text not null default 'app'" },
      { name: "employee_id", type: "uuid" },
    ],
  },
} as const;

const COLUMNS = {
  leave_request: {
    source: "'hr'",
    employee_id:
      "(select e.id from better_supabase.employees e where e.tenant_id = subject.tenant and e.user_id = subject.requested_by)",
  },
};

describe("approvals requestColumns", { timeout: 180_000 }, () => {
  it("fills the app's columns of a request a block files", async () => {
    const files = renderBlocks(["employees", "leave"], {
      ...LAYOUT,
      modules: { approvals: { options: { requestColumns: COLUMNS } } },
    });

    await using stack = await liteStack({
      driver: "pglite",
      migrations: [
        ROLES,
        ...files
          .filter((file) => file.kind === "schema")
          .map((file) => file.contents),
        ADDED,
      ],
      seed: [
        ...files
          .filter((file) => file.kind === "data")
          .map((file) => file.contents),
        ALLOW,
        `do $$
declare
  v_type uuid;
  v_id uuid;
  v_request better_supabase.approval_requests%rowtype;
begin
  ${AS_ALICE}
  v_type := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday', 'days', true, false) ->> 'id')::uuid;
  v_id := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03') ->> 'id')::uuid;
  select a.* into v_request from better_supabase.approval_requests a
    join better_supabase.leave_requests r on r.approval_id = a.id where r.id = v_id;
  if v_request.source is distinct from 'hr' or v_request.employee_id is distinct from '${ALICE_EMPLOYEE}'::uuid then
    raise exception 'the request columns are not filled: %', to_jsonb(v_request);
  end if;
end;
$$;`,
      ],
    });

    expect(stack.url).not.toBe("");
  });

  it("refuses a column the app doesn't add", () => {
    expect(() =>
      renderBlocks(["employees", "leave"], {
        ...LAYOUT,
        modules: {
          approvals: {
            options: { requestColumns: { leave_request: { origin: "'hr'" } } },
          },
        },
      }),
    ).toThrow(/requestColumns\.leave_request\.origin/u);
  });

  it("refuses a value that isn't one expression", () => {
    expect(() =>
      renderBlocks(["employees", "leave"], {
        ...LAYOUT,
        modules: {
          approvals: {
            options: {
              requestColumns: {
                leave_request: { source: "'a'; drop table x" },
              },
            },
          },
        },
      }),
    ).toThrow(/one SQL expression/u);
  });
});
