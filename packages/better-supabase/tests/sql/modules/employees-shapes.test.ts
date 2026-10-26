import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const USER = "22222222-2222-4222-8222-222222222222";

const SETUP = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create type public.staff_kind as enum ('staff', 'freelance', 'trainee');
create type public.staff_status as enum ('onboarding', 'active', 'offboarding', 'ended');
create table public.staff (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  user_id uuid,
  name text not null,
  manager_id uuid references public.staff (id),
  kind public.staff_kind not null default 'staff',
  status public.staff_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.staff_contracts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  employee_id uuid not null references public.staff (id) on delete cascade,
  starts_on date not null,
  ends_on date,
  hours_per_week numeric(5, 2),
  pay numeric(12, 2),
  currency text,
  created_at timestamptz not null default now()
);
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role","sub":"${USER}"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '${USER}', true);`;

const blocks = (
  contracts: Readonly<Record<string, string | null>>,
  options: Readonly<Record<string, string>> = {},
): AnyBlocksConfig => ({
  employees: {
    tables: {
      employees: "public.staff",
      privateDetails: null,
      contracts: "public.staff_contracts",
    },
    columns: {
      employees: {
        employmentType: "kind",
        email: null,
        jobTitle: null,
        team: null,
        startDate: null,
        endDate: null,
        offboardReason: null,
        originType: null,
        originId: null,
        createdBy: null,
      },
      contracts: {
        salaryPeriod: null,
        note: null,
        createdBy: null,
        ...contracts,
      },
    },
    values: {
      employees: {
        employmentType: {
          employee: "staff",
          contractor: "freelance",
          intern: "trainee",
          temporary: null,
        },
        status: {
          preboarding: "onboarding",
          active: ["active", "offboarding"],
          on_leave: null,
          offboarded: "ended",
        },
      },
    },
    options: { contracts: "editable", ...options },
    permissions: {
      create: "staff.create",
      contractsRead: "staff.contracts_read",
      contractsWrite: "staff.contracts_write",
    },
  },
});

const render = (modules: AnyBlocksConfig): string =>
  renderBlocks(["employees"], {
    modules,
    ownTables: {
      "public.staff": "app.sql",
      "public.staff_contracts": "app.sql",
    },
  })
    .filter((file) => file.module === "employees")
    .map((file) => file.contents)
    .join("\n");

describe("employees over app tables with their own shapes", () => {
  it("checks the per-action keys it is given", () => {
    const sql = render(blocks({ salary: "pay" }));

    expect(sql).toContain("'staff.create'");
    expect(sql).toContain("'staff.contracts_read'");
    expect(sql).toContain("'staff.contracts_write'");
    expect(sql).not.toContain("save_employee_private_details");
  });

  it("refuses an overlap option without editable contracts", () => {
    expect(() =>
      render(
        blocks(
          { salary: "pay" },
          { contracts: "append", contractOverlap: "allow" },
        ),
      ),
    ).toThrow('contractOverlap "allow" needs contracts "editable"');
  });

  it(
    "writes mapped enum types and statuses, major-unit salaries and side-by-side contracts",
    { timeout: 60_000 },
    async () => {
      const files = renderBlocks(["employees"], {
        modules: blocks(
          { salary: "pay" },
          { salaryUnits: "major", contractOverlap: "allow" },
        ),
        ownTables: {
          "public.staff": "app.sql",
          "public.staff_contracts": "app.sql",
        },
      });

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          SETUP,
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
  v_employee jsonb;
  v_id uuid;
  v_result jsonb;
  v_contracts jsonb;
begin
  ${SERVICE}
  v_employee := better_supabase.create_employee('${TENANT}', '{"name": "Ada", "employmentType": "intern"}'::jsonb);
  v_id := (v_employee ->> 'id')::uuid;
  if (select kind::text from public.staff where id = v_id) <> 'trainee' then
    raise exception 'type %', v_employee;
  end if;
  v_result := better_supabase.update_employees(jsonb_build_array(
    jsonb_build_object('employeeId', v_id, 'field', 'employmentType', 'value', 'contractor'),
    jsonb_build_object('employeeId', v_id, 'field', 'status', 'value', 'offboarding')));
  if jsonb_array_length(v_result -> 'accepted') <> 2
    or (select kind::text from public.staff where id = v_id) <> 'freelance'
    or (select status::text from public.staff where id = v_id) <> 'offboarding' then
    raise exception 'update %', v_result;
  end if;
  perform better_supabase.add_employee_contract(v_id, '{"startsOn": "2026-01-01", "salary": "540000", "currency": "eur"}'::jsonb);
  perform better_supabase.add_employee_contract(v_id, '{"startsOn": "2025-06-01", "salary": "1000", "currency": "jpy"}'::jsonb);
  if (select pay from public.staff_contracts where currency = 'EUR') <> 5400
    or (select pay from public.staff_contracts where currency = 'JPY') <> 1000
    or exists (select 1 from public.staff_contracts where ends_on is not null) then
    raise exception 'contracts %', (select jsonb_agg(c) from public.staff_contracts c);
  end if;
  v_contracts := better_supabase.employee_contracts(v_id);
  if v_contracts -> 0 ->> 'pay' <> '540000' then
    raise exception 'read %', v_contracts;
  end if;
end;
$$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );

  it("runs contracts without salary columns", { timeout: 60_000 }, async () => {
    const files = renderBlocks(["employees"], {
      modules: blocks({ salary: null, currency: null }),
      ownTables: {
        "public.staff": "app.sql",
        "public.staff_contracts": "app.sql",
      },
    });

    await using stack = await liteStack({
      driver: "pglite",
      migrations: [
        SETUP,
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
  v_id uuid;
  v_contract jsonb;
begin
  ${SERVICE}
  v_id := (better_supabase.create_employee('${TENANT}', '{"name": "Grace"}'::jsonb) ->> 'id')::uuid;
  v_contract := better_supabase.add_employee_contract(v_id, '{"startsOn": "2026-01-01", "hoursPerWeek": 32}'::jsonb);
  v_contract := better_supabase.update_employee_contract((v_contract ->> 'id')::uuid, '{"hoursPerWeek": 36}'::jsonb);
  if (select hours_per_week from public.staff_contracts) <> 36 or (select kind::text from public.staff) <> 'staff' then
    raise exception 'contract %', v_contract;
  end if;
end;
$$;`,
      ],
    });

    expect(stack.url).not.toBe("");
  });

  it(
    "keeps column defaults, writes extras in the insert and returns the block's keys",
    { timeout: 60_000 },
    async () => {
      const modules: AnyBlocksConfig = {
        employees: {
          tables: {
            employees: "public.people",
            privateDetails: null,
            contracts: "public.people_contracts",
          },
          columns: {
            employees: {
              tenant: "org_id",
              startDate: "starts_on",
              email: null,
              jobTitle: null,
              team: null,
              endDate: null,
              offboardReason: null,
              originType: null,
              originId: null,
              createdBy: null,
            },
            contracts: {
              tenant: "org_id",
              salary: "pay_cents",
              salaryPeriod: null,
              note: null,
              createdBy: null,
            },
          },
          values: { employees: { status: { active: "working" } } },
          options: {
            contractExtraColumns: {
              is_flexible: "boolean not null default false",
              weekly_hours: "numeric(5, 2)",
            },
          },
        },
      };

      const files = renderBlocks(["employees"], {
        modules,
        ownTables: {
          "public.people": "app.sql",
          "public.people_contracts": "app.sql",
        },
      });

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          `do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create table public.people (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  user_id uuid,
  name text not null,
  manager_id uuid references public.people (id),
  employment_type text not null default 'employee',
  status text not null default 'working',
  starts_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.people_contracts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  employee_id uuid not null references public.people (id) on delete cascade,
  starts_on date not null,
  ends_on date,
  hours_per_week numeric(5, 2),
  pay_cents bigint,
  currency text not null default 'EUR',
  is_flexible boolean not null default false,
  weekly_hours numeric(5, 2),
  created_at timestamptz not null default now(),
  check (is_flexible or weekly_hours is not null)
);`,
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
  v_employee jsonb;
  v_id uuid;
  v_contract jsonb;
begin
  ${SERVICE}
  v_employee := better_supabase.create_employee('${TENANT}', '{"name": "Ada", "startDate": "2026-01-01"}'::jsonb);
  v_id := (v_employee ->> 'id')::uuid;
  if v_employee ->> 'tenant_id' <> '${TENANT}' or v_employee ->> 'status' <> 'active'
    or v_employee ->> 'start_date' <> '2026-01-01' then
    raise exception 'employee %', v_employee;
  end if;
  v_contract := better_supabase.add_employee_contract(v_id, '{"startsOn": "2026-01-01", "fields": {"weekly_hours": 38}}'::jsonb);
  if (select currency from public.people_contracts) <> 'EUR'
    or (select weekly_hours from public.people_contracts) <> 38 then
    raise exception 'contract %', (select jsonb_agg(c) from public.people_contracts c);
  end if;
  v_contract := better_supabase.add_employee_contract(v_id, '{"startsOn": "2026-06-01", "salary": "420000", "currency": "usd", "fields": {"is_flexible": true}}'::jsonb);
  if v_contract ->> 'salary' <> '420000' or v_contract ->> 'tenant_id' <> '${TENANT}' or v_contract ->> 'currency' <> 'USD' then
    raise exception 'read %', v_contract;
  end if;
end;
$$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );
});
