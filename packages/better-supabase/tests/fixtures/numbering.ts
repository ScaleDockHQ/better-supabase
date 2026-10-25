import { expect } from "vitest";

import { renderBlocks } from "../../src/sql/render.ts";
import { liteStack } from "../../src/testing/lite.ts";

export const ALICE = "11111111-1111-4111-8111-111111111111";
export const BOB = "22222222-2222-4222-8222-222222222222";
export const YEAR = "to_char(now() at time zone 'utc', 'YYYY')";

const INVOICES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  number text,
  unique (organization_id, number)
);
`;

const SEEDED = `
insert into public.invoices (organization_id, number) values
  ('${ALICE}', 'INV-2020-0007'),
  ('${ALICE}', 'INV-' || ${YEAR} || '-0001'),
  ('${ALICE}', 'INV-' || ${YEAR} || '-0012'),
  ('${BOB}', 'INV-' || ${YEAR} || '-0002'),
  ('${BOB}', 'imported-without-format');
`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
export const BOOT = { timeout: 60_000 };

export async function withNumbers(
  entities: Record<string, unknown>,
  ddl: string,
  seed: readonly string[],
  block: Record<string, unknown> = {},
): Promise<void> {
  const files = renderBlocks(["numbering"], {
    modules: { numbering: { ...block, options: { entities } } },
  });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ddl,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      ...seed,
    ],
  });

  expect(stack.url).not.toBe("");
}

export const withInvoices = (check: string): Promise<void> =>
  withNumbers(
    {
      invoice: {
        period: "year",
        format: "INV-{yyyy}-{n:4}",
        table: "public.invoices",
        column: "number",
        tenantColumn: "organization_id",
      },
    },
    INVOICES,
    [SEEDED, check],
  );

export const ISSUED: string = `${INVOICES}
alter table public.invoices
  add column status text not null default 'draft',
  add column issued_on date;
`;

export const issued = (check: string): Promise<void> =>
  withNumbers(
    {
      invoice: {
        period: "year",
        format: "INV-{yyyy}-{n:4}",
        table: "public.invoices",
        column: "number",
        tenantColumn: "organization_id",
        periodColumn: "issued_on",
        assignOn: "new.status = 'sent'",
      },
    },
    ISSUED,
    [check],
  );

export const CAROL = "33333333-3333-4333-8333-333333333333";

const TENANT_FORMATS = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;

create table public.organizations (
  id uuid primary key,
  invoice_number_format text,
  invoice_number_reset text
);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id),
  status text not null default 'draft',
  issued_on date,
  number bigint,
  formatted_number text,
  unique (organization_id, formatted_number)
);
`;

export const ORGANIZATIONS: string = `
insert into public.organizations (id, invoice_number_format) values
  ('${ALICE}', '{yyyy}-{n:3}'),
  ('${BOB}', null),
  ('${CAROL}', 'F{yy}{mm}-{n}');
`;

export const perTenant = {
  period: "format",
  format: "{n}",
  formatFrom: { column: "public.organizations.invoice_number_format" },
  table: "public.invoices",
  column: "formatted_number",
  tenantColumn: "organization_id",
  periodColumn: "issued_on",
  assignOn: "new.status = 'sent'",
};

export const tenantFormats = (
  check: string,
  entity: Record<string, unknown> = {},
): Promise<void> =>
  withNumbers({ invoice: { ...perTenant, ...entity } }, TENANT_FORMATS, [
    ORGANIZATIONS,
    check,
  ]);

export const send = (
  tenant: string,
  issued: string,
  expected: string,
): string =>
  `  insert into public.invoices (organization_id, status, issued_on) values ('${tenant}', 'sent', '${issued}') returning formatted_number into v_number;
  if v_number is distinct from '${expected}' then
    raise exception 'numbered % for ${tenant} on ${issued}, expected ${expected}', v_number;
  end if;`;

const RESETS = `update public.organizations set invoice_number_format = 'INV-{yyyy}{mm}-{n}', invoice_number_reset = 'year' where id = '${ALICE}';
update public.organizations set invoice_number_format = '{yyyy}-{n}', invoice_number_reset = 'none' where id = '${BOB}';`;

export const resets = (
  check: string,
  entity: Record<string, unknown> = {},
): Promise<void> =>
  tenantFormats(`${RESETS}\n${check}`, {
    periodFrom: { column: "public.organizations.invoice_number_reset" },
    ...entity,
  });

export const GENERATED_PERIOD: string = `${TENANT_FORMATS}
alter table public.organizations
  add column invoice_number_period text generated always as (
    case invoice_number_reset when 'never' then 'none' when 'yearly' then 'year' end
  ) stored;
`;

const CAN = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean
language sql
stable
as $$ select scope_id = '${ALICE}' and permission = 'invoices.write' $$;
`;

export const asMember = (check: string): string =>
  `select set_config('request.jwt.claims', '{"role":"authenticated"}', false);
${check}`;

export const previews = (check: string): Promise<void> =>
  withNumbers(
    { invoice: { ...perTenant, sequenceColumn: "number" } },
    TENANT_FORMATS,
    [ORGANIZATIONS, CAN, check],
    { permissions: { assign: "invoices.write" } },
  );

export const entityPreviews = (check: string): Promise<void> =>
  withNumbers(
    {
      invoice: {
        ...perTenant,
        sequenceColumn: "number",
        permission: "invoices.write",
      },
      quote: { period: "year", format: "Q-{yyyy}-{n}" },
    },
    TENANT_FORMATS,
    [ORGANIZATIONS, CAN, check],
  );
