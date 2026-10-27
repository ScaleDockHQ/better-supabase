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
create type public.pay_basis as enum ('hourly', 'monthly', 'annual');
create table public.staff (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  user_id uuid,
  first_name text not null,
  last_name text,
  full_name text generated always as (trim(first_name || coalesce(' ' || last_name, ''))) stored,
  manager_id uuid references public.staff (id),
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.staff_private (
  employee_id uuid primary key references public.staff (id) on delete cascade,
  tenant_id uuid not null,
  birth_date date,
  home_line1 text,
  home_postal_code text,
  home_city text,
  home_country text,
  emergency_name text,
  emergency_phone text,
  updated_at timestamptz not null default now()
);
create table public.staff_contracts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  employee_id uuid not null references public.staff (id) on delete cascade,
  starts_on date not null,
  ends_on date,
  hours_per_week numeric(5, 2),
  salary bigint,
  currency text,
  pay_basis public.pay_basis,
  created_at timestamptz not null default now()
);
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role","sub":"${USER}"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '${USER}', true);`;

const columns = (name: string | null) => ({
  employees: {
    name,
    firstName: "first_name",
    lastName: "last_name",
    manager: "manager_id",
    email: null,
    jobTitle: null,
    team: null,
    employmentType: null,
    startDate: null,
    endDate: null,
    offboardReason: null,
    originType: null,
    originId: null,
    createdBy: null,
  },
  privateDetails: {
    user: null,
    nationalId: null,
    iban: null,
    personalEmail: null,
    phone: null,
    address: null,
    emergencyContacts: null,
    offboardedAt: null,
    anonymizedAt: null,
    updatedBy: null,
    addressLine1: "home_line1",
    addressLine2: null,
    postalCode: "home_postal_code",
    city: "home_city",
    region: null,
    country: "home_country",
    emergencyName: "emergency_name",
    emergencyPhone: "emergency_phone",
    emergencyRelation: null,
  },
  contracts: { salaryPeriod: "pay_basis", note: null, createdBy: null },
});

const blocks = (name: string | null): AnyBlocksConfig => ({
  employees: {
    tables: {
      employees: "public.staff",
      privateDetails: "public.staff_private",
      contracts: "public.staff_contracts",
    },
    columns: columns(name),
    values: {
      contracts: {
        salaryPeriod: {
          hour: "hourly",
          month: "monthly",
          year: "annual",
          week: null,
        },
      },
    },
    options: { name: "split", privateDetails: "flat", contracts: "editable" },
  },
});

const render = (modules: AnyBlocksConfig) =>
  renderBlocks(["employees"], {
    modules,
    ownTables: {
      "public.staff": "app.sql",
      "public.staff_private": "app.sql",
      "public.staff_contracts": "app.sql",
    },
  });

async function run(
  modules: AnyBlocksConfig,
  check: string,
  setup = SETUP,
): Promise<void> {
  const files = render(modules);

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      setup,
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

const BOOT = { timeout: 60_000 };

describe("employees over the app's tables", () => {
  it("refuses a null name without the split option", () => {
    expect(() =>
      render({ employees: { ...blocks(null)["employees"], options: {} } }),
    ).toThrow(/options.name "split"/u);
  });

  it("renders split names, flat details and editable contracts on managed tables", () => {
    const sql = renderBlocks(["employees"], {
      modules: {
        employees: {
          columns: {
            privateDetails: {
              user: null,
              address: null,
              emergencyContacts: null,
            },
          },
          options: {
            name: "split",
            privateDetails: "flat",
            contracts: "editable",
          },
        },
      },
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain('"first_name" text not null');
    expect(sql).toContain(
      `"name" text generated always as (trim("first_name" || coalesce(' ' || "last_name", ''))) stored`,
    );
    expect(sql).toContain('"address_line1" text check');
    expect(sql).toContain('"emergency_contact_relation" text check');
    expect(sql).toContain("update_employee_contract");
    expect(sql).not.toContain('"emergency_contacts" jsonb');

    const firstOnly = renderBlocks(["employees"], {
      modules: {
        employees: {
          columns: { employees: { name: null, lastName: null } },
          options: { name: "split" },
        },
      },
    })
      .map((file) => file.contents)
      .join("\n");

    expect(firstOnly).toContain('"first_name" text not null');
    expect(firstOnly).not.toContain("generated always");
  });

  it("names a hire from a fixed candidate type", () => {
    const sql = renderBlocks(["hiring", "employees"], {
      modules: {
        hiring: {
          columns: { applications: { candidateType: null } },
          options: { candidate: "person" },
        },
      },
      subjects: {
        person: { table: "public.people", idType: "uuid", title: "full_name" },
      },
    })
      .filter((file) => file.module === "employees")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("employee_from_application");
    expect(sql).toContain(`case 'person'`);
  });

  it("refuses unknown options and a split name without a first name column", () => {
    expect(() =>
      renderBlocks(["employees"], {
        modules: { employees: { options: { name: "full" } } },
      }),
    ).toThrow(/options.name must be/u);
    expect(() =>
      renderBlocks(["employees"], {
        modules: {
          employees: {
            columns: { employees: { firstName: null } },
            options: { name: "split" },
          },
        },
      }),
    ).toThrow(/firstName can't be null/u);
  });

  it("leaves the update and delete of contracts out by default", () => {
    const sql = renderBlocks(["employees"], { modules: {} })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("update_employee_contract");
    expect(sql).toContain("add_employee_contract");
  });

  it(
    "writes first and last names, flat details and editable contracts with a generated name",
    BOOT,
    async () => {
      await expect(
        run(
          blocks("full_name"),
          `do $$
declare
  v_employee jsonb;
  v_id uuid;
  v_details jsonb;
  v_contract jsonb;
  v_result jsonb;
begin
  ${SERVICE}
  v_employee := better_supabase.create_employee('${TENANT}', '{"name": "Ada Lovelace King"}'::jsonb);
  v_id := (v_employee ->> 'id')::uuid;
  if (select first_name from public.staff where id = v_id) <> 'Ada'
    or (select last_name from public.staff where id = v_id) <> 'Lovelace King'
    or v_employee ->> 'full_name' <> 'Ada Lovelace King' then
    raise exception 'create %', v_employee;
  end if;
  v_result := better_supabase.update_employees(jsonb_build_array(
    jsonb_build_object('employeeId', v_id, 'field', 'lastName', 'value', 'Byron')));
  if jsonb_array_length(v_result -> 'accepted') <> 1
    or (select full_name from public.staff where id = v_id) <> 'Ada Byron' then
    raise exception 'update %', v_result;
  end if;
  v_details := better_supabase.save_employee_private_details(v_id, '{"address": {"line1": "1 Main St", "city": "London", "country": "GB"}, "emergencyContacts": [{"name": "Charles", "phone": "+44 1"}]}'::jsonb);
  if (select home_city from public.staff_private where employee_id = v_id) <> 'London'
    or (select emergency_name from public.staff_private where employee_id = v_id) <> 'Charles'
    or v_details -> 'address' ->> 'line1' <> '1 Main St'
    or v_details -> 'emergency_contacts' -> 0 ->> 'phone' <> '+44 1' then
    raise exception 'details %', v_details;
  end if;
  v_details := better_supabase.save_employee_private_details(v_id, '{"postalCode": "NW1"}'::jsonb);
  if (select home_postal_code from public.staff_private where employee_id = v_id) <> 'NW1'
    or (select home_city from public.staff_private where employee_id = v_id) <> 'London' then
    raise exception 'flat key %', v_details;
  end if;
  v_contract := better_supabase.add_employee_contract(v_id, '{"startsOn": "2026-01-01", "salary": "500000", "currency": "eur", "salaryPeriod": "month"}'::jsonb);
  if (select pay_basis::text from public.staff_contracts) <> 'monthly' then
    raise exception 'contract %', v_contract;
  end if;
  v_contract := better_supabase.update_employee_contract((v_contract ->> 'id')::uuid, '{"salaryPeriod": "year", "salary": null, "endsOn": "2026-12-31"}'::jsonb);
  if (select pay_basis::text from public.staff_contracts) <> 'annual'
    or (select salary from public.staff_contracts) is not null
    or (select currency from public.staff_contracts) <> 'EUR'
    or (select ends_on from public.staff_contracts) <> '2026-12-31' then
    raise exception 'contract update %', v_contract;
  end if;
  perform better_supabase.delete_employee_contract((v_contract ->> 'id')::uuid);
  if exists (select 1 from public.staff_contracts) then
    raise exception 'contract not deleted';
  end if;
end;
$$;`,
        ),
      ).resolves.toBeUndefined();
    },
  );

  it("reads the name from the parts without a name column", BOOT, async () => {
    await expect(
      run(
        blocks(null),
        `do $$
declare
  v_employee jsonb;
  v_chart jsonb;
begin
  ${SERVICE}
  v_employee := better_supabase.create_employee('${TENANT}', '{"firstName": "Grace", "lastName": "Hopper"}'::jsonb);
  if v_employee ->> 'name' <> 'Grace Hopper' then
    raise exception 'name %', v_employee;
  end if;
  v_chart := better_supabase.org_chart('${TENANT}', null);
  if v_chart -> 0 ->> 'name' <> 'Grace Hopper' then
    raise exception 'chart %', v_chart;
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it(
    "maps an enum status and fills extra column defaults on create, and keeps a required currency",
    BOOT,
    async () => {
      const setup = `${SETUP}
create type public.staff_status as enum ('onboarding', 'active', 'ended');
alter table public.staff alter column status drop default;
alter table public.staff alter column status type public.staff_status using status::public.staff_status;
alter table public.staff alter column status set default 'active';
alter table public.staff add column show_birthday boolean not null default false;
alter table public.staff add column timezone text;
update public.staff_contracts set currency = 'EUR' where currency is null;
alter table public.staff_contracts alter column currency set not null;
`;

      const config = blocks("full_name");

      await expect(
        run(
          {
            employees: {
              ...config["employees"],
              values: {
                ...config["employees"]?.values,
                employees: {
                  status: {
                    preboarding: "onboarding",
                    active: "active",
                    offboarded: "ended",
                    on_leave: null,
                  },
                },
              },
              options: {
                ...config["employees"]?.options,
                extraColumns: {
                  show_birthday: "boolean not null default false",
                  timezone: "text",
                },
              },
            },
          },
          `do $$
declare
  v_employee jsonb;
  v_contract jsonb;
begin
  ${SERVICE}
  v_employee := better_supabase.create_employee('${TENANT}', '{"name": "Sam Lee", "status": "preboarding", "timezone": "Europe/Amsterdam"}'::jsonb);
  if (select status::text from public.staff where id = (v_employee ->> 'id')::uuid) <> 'onboarding'
    or (select show_birthday from public.staff where id = (v_employee ->> 'id')::uuid) <> false
    or (select timezone from public.staff where id = (v_employee ->> 'id')::uuid) <> 'Europe/Amsterdam' then
    raise exception 'create %', v_employee;
  end if;
  v_contract := better_supabase.add_employee_contract((v_employee ->> 'id')::uuid, '{"startsOn": "2026-01-01", "salary": "500000", "currency": "EUR"}'::jsonb);
  v_contract := better_supabase.update_employee_contract((v_contract ->> 'id')::uuid, '{"salary": null}'::jsonb);
  if (select salary from public.staff_contracts) is not null
    or (select currency from public.staff_contracts) <> 'EUR' then
    raise exception 'contract update %', v_contract;
  end if;
end;
$$;`,
          setup,
        ),
      ).resolves.toBeUndefined();
    },
  );
});
