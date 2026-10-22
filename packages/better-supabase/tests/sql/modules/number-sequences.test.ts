import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const sqlOf = (modules: AnyBlocksConfig = {}): string =>
  renderBlocks(["number-sequences"], { modules })
    .filter((file) => file.module === "number-sequences")
    .map((file) => file.contents)
    .join("\n");

describe("number sequences", () => {
  it("allocates inside the caller's transaction and keeps the function service-only", () => {
    const sql = sqlOf();
    expect(sql).toContain("on conflict");
    expect(sql).toContain("last_number");
    expect(sql).toContain("grant execute on function");
    expect(sql).toContain("to service_role");
    expect(sql).not.toContain(
      '"next_number"(uuid, text, timestamptz) to authenticated',
    );
    expect(sql).toContain(
      'grant execute on function "better_supabase"."preview_number"(uuid, text, timestamptz) to authenticated, service_role;',
    );
    expect(sql).toContain(
      "coalesce(better_supabase.can('tenant', p_tenant, 'number_sequences.assign'), false)",
    );
    expect(sql).toContain("ACTOR_READ_ONLY");
    expect(sql).toContain("on conflict");
  });

  it("resets the period and fills a column when a document is issued", () => {
    const sql = sqlOf({
      "number-sequences": {
        options: {
          entities: {
            invoice: {
              period: "year",
              format: "INV-{yyyy}-{n:5}",
              table: "public.invoices",
              column: "number",
              assignOn: "new.status = 'sent'",
              tenantColumn: "organization_id",
            },
            order: {
              period: { fiscalYearStartMonth: 4 },
              format: "PO-{yyyy}-{n}",
            },
          },
        },
      },
    });

    expect(sql).toContain("to_char(next_number.at at time zone 'utc', 'YYYY')");
    expect(sql).toContain(
      "extract(month from next_number.at at time zone 'utc') >= 4",
    );
    expect(sql).toContain("new.status = 'sent'");
    expect(sql).toContain("NUMBER_IMMUTABLE");
    expect(sql).toContain("organization_id");
    expect(sql).toContain("INV-{yyyy}-{n:5}");
  });

  it("refuses a predicate that is not an expression", () => {
    expect(() =>
      sqlOf({
        "number-sequences": {
          options: {
            entities: {
              invoice: {
                period: "none",
                format: "{n}",
                table: "public.invoices",
                column: "number",
                assignOn: "new.status = 'sent'; drop table invoices",
              },
            },
          },
        },
      }),
    ).toThrow(/assignOn/);
  });

  const assignOn = (predicate: string) => () =>
    sqlOf({
      "number-sequences": {
        options: {
          entities: {
            invoice: {
              period: "none",
              format: "{n}",
              table: "public.invoices",
              column: "number",
              assignOn: predicate,
            },
          },
        },
      },
    });

  it.each([
    "new.status in ('sent', 'overdue')",
    "new.status not in ('sent','overdue') and new.kind IN (1, 2.5, -3)",
    "new.status = 'sent' or new.\"Kind\" in ('it''s', 'a,b')",
    "new.note = 'a, b'",
  ])("accepts the predicate %s", (predicate) => {
    expect(assignOn(predicate)()).toContain(predicate);
  });

  it.each([
    "coalesce(new.status, 'sent') = 'sent'",
    "new.status in ('sent', new.other)",
    "new.status in ('sent', 'overdue'",
    "f(' in (', 1, ')') = 'x'",
    "new.status = 'sent",
    "new.status in ('sent'); drop table invoices",
  ])("refuses the predicate %s", (predicate) => {
    expect(assignOn(predicate)).toThrow(/assignOn/);
  });

  it("syncs counters from the numbers a table already holds", () => {
    const sql = sqlOf({
      "number-sequences": {
        options: {
          entities: {
            invoice: {
              period: "year",
              format: "INV-{yyyy}-{n:5}",
              table: "public.invoices",
              column: "number",
              tenantColumn: "organization_id",
            },
            order: {
              period: { fiscalYearStartMonth: 4 },
              format: "PO.{yy}{mm}/{n}",
              table: "public.orders",
              column: "number",
            },
            receipt: {
              period: "month",
              format: "R-{n}",
              table: "public.receipts",
              column: "number",
              periodColumn: "issued_at",
            },
            quote: {
              period: "year",
              format: "Q-{n}",
              table: "public.quotes",
              column: "number",
            },
            credit: { period: "none", format: "CR-{n}" },
          },
        },
      },
    });

    expect(sql).toContain(
      '"better_supabase"."sync_number_sequences"(p_tenant uuid default null, p_entity text default null)',
    );
    expect(sql).toContain(
      "p_entity in ('invoice', 'order', 'receipt', 'quote')",
    );
    expect(sql).toContain(
      "regexp_match(t.\"number\"::text, '^INV-([0-9]{4})-([0-9]+)$')",
    );
    expect(sql).toContain(
      'select t."organization_id" as tenant, m.parts[1] as period, (m.parts[2])::bigint as n',
    );
    expect(sql).toContain("'^PO\\.([0-9]{2})([0-9]{2})/([0-9]+)$'");
    expect(sql).toContain(
      "case when m.parts[2]::int >= 4 then '20' || m.parts[1] else (('20' || m.parts[1])::int - 1)::text end",
    );
    expect(sql).toContain(
      "to_char(better_supabase.number_at(t.\"issued_at\") at time zone 'utc', 'YYYY-MM')",
    );
    expect(sql).toContain(
      'v_at := coalesce(better_supabase.number_at(new."issued_at"), now());',
    );
    expect(sql).toContain("v_at := now();");
    expect(sql).toContain(
      "the quote format holds no period; set options.entities.quote.periodColumn",
    );
    expect(sql).toContain(
      'greatest("better_supabase"."number_sequences"."last_number", excluded."last_number")',
    );
    expect(sql).toContain(
      'grant execute on function "better_supabase"."sync_number_sequences"(uuid, text) to service_role;',
    );
  });

  it("numbers by month and without a period", () => {
    const sql = sqlOf({
      "number-sequences": {
        options: {
          entities: {
            ticket: { period: "month", format: "T-{yyyy}-{mm}-{n}" },
            quote: {
              period: "none",
              format: "Q-{n}",
              table: "public.quotes",
              column: "number",
            },
          },
        },
      },
    });

    expect(sql).toContain("'YYYY-MM'");
    expect(sql).toContain("Q-{n}");
  });

  it.each([
    ["entities that are not an object", ["invoice"], /must be an object of/],
    ["an entity name with capitals", { Invoice: {} }, /lowercase letters/],
    [
      "an entity that is not an object",
      { invoice: "year" },
      /must be an object/,
    ],
    ["an unknown period", { invoice: { period: "week" } }, /period must be/],
    [
      "a fiscal month out of range",
      { invoice: { period: { fiscalYearStartMonth: 13 }, format: "{n}" } },
      /fiscalYearStartMonth/,
    ],
    ["a missing format", { invoice: { period: "year" } }, /format/],
    [
      "a table that is not text",
      { invoice: { period: "year", format: "{n}", table: 1, column: "n" } },
      /table must be/,
    ],
    [
      "a column that is not a name",
      {
        invoice: {
          period: "year",
          format: "{n}",
          table: "public.invoices",
          column: "Number",
        },
      },
      /column must be/,
    ],
    [
      "a table without a column",
      { invoice: { period: "year", format: "{n}", table: "public.invoices" } },
      /both table and column/,
    ],
    [
      "a tenant column that is not a name",
      { invoice: { period: "year", format: "{n}", tenantColumn: "Org" } },
      /tenantColumn/,
    ],
  ])("refuses %s", (_label, entities, message) => {
    expect(() =>
      sqlOf({ "number-sequences": { options: { entities } } }),
    ).toThrow(message);
  });

  it("refuses a periodColumn that is not a column name", () => {
    expect(() =>
      sqlOf({
        "number-sequences": {
          options: {
            entities: {
              invoice: {
                period: "year",
                format: "{n}",
                table: "public.invoices",
                column: "number",
                periodColumn: "issued_at; drop table invoices",
              },
            },
          },
        },
      }),
    ).toThrow(/periodColumn/);
  });
});

const ALICE = "11111111-1111-4111-8111-111111111111";
const BOB = "22222222-2222-4222-8222-222222222222";
const YEAR = "to_char(now() at time zone 'utc', 'YYYY')";

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
const BOOT = { timeout: 60_000 };

async function withNumbers(
  entities: Record<string, unknown>,
  ddl: string,
  seed: readonly string[],
  block: Record<string, unknown> = {},
): Promise<void> {
  const files = renderBlocks(["number-sequences"], {
    modules: { "number-sequences": { ...block, options: { entities } } },
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

const withInvoices = (check: string): Promise<void> =>
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

describe("sync_number_sequences", BOOT, () => {
  it("numbers past the seeded rows after a sync, per tenant and period", async () => {
    await expect(
      withInvoices(`do $$
declare
  v_synced integer;
  v_number text;
begin
  v_synced := better_supabase.sync_number_sequences();
  if v_synced <> 3 then
    raise exception 'synced % counters', v_synced;
  end if;
  insert into public.invoices (organization_id) values ('${ALICE}') returning number into v_number;
  if v_number <> 'INV-' || ${YEAR} || '-0013' then
    raise exception 'numbered %', v_number;
  end if;
  insert into public.invoices (organization_id) values ('${BOB}') returning number into v_number;
  if v_number <> 'INV-' || ${YEAR} || '-0003' then
    raise exception 'numbered %', v_number;
  end if;
  perform better_supabase.sync_number_sequences('${ALICE}', 'invoice');
  if (select last_number from better_supabase.number_sequences where tenant_id = '${ALICE}' and period = ${YEAR}) <> 13 then
    raise exception 'a second sync lowered the counter';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("collides without a sync, and refuses an entity without a table", async () => {
    await expect(
      withInvoices(
        `insert into public.invoices (organization_id) values ('${ALICE}');`,
      ),
    ).rejects.toThrow(/duplicate key value/);
    await expect(
      withInvoices(
        "select better_supabase.sync_number_sequences(null, 'quote');",
      ),
    ).rejects.toThrow(/no numbered table for this sequence/);
  });
});

const ISSUED = `${INVOICES}
alter table public.invoices
  add column status text not null default 'draft',
  add column issued_on date;
`;

const issued = (check: string): Promise<void> =>
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

describe("assignOn lists", BOOT, () => {
  it("numbers a row when its status enters the list", async () => {
    await expect(
      withNumbers(
        {
          invoice: {
            period: "none",
            format: "INV-{n}",
            table: "public.invoices",
            column: "number",
            tenantColumn: "organization_id",
            assignOn: "new.status in ('sent', 'overdue')",
          },
        },
        ISSUED,
        [
          `do $$
declare
  v_id uuid;
  v_number text;
begin
  insert into public.invoices (organization_id) values ('${ALICE}') returning id into v_id;
  update public.invoices set status = 'review' where id = v_id returning number into v_number;
  if v_number is not null then
    raise exception 'numbered % in review', v_number;
  end if;
  update public.invoices set status = 'overdue' where id = v_id returning number into v_number;
  if v_number is distinct from 'INV-1' then
    raise exception 'numbered %', v_number;
  end if;
  insert into public.invoices (organization_id, status) values ('${ALICE}', 'sent') returning number into v_number;
  if v_number is distinct from 'INV-2' then
    raise exception 'numbered %', v_number;
  end if;
end;
$$;`,
        ],
      ),
    ).resolves.toBeUndefined();
  });
});

describe("periodColumn at assignment", BOOT, () => {
  it("takes the period and the date tokens from the row's issue date", async () => {
    await expect(
      issued(`set timezone = 'Europe/Amsterdam';
do $$
declare
  v_id uuid;
  v_number text;
begin
  insert into public.invoices (organization_id, issued_on) values ('${ALICE}', '2025-01-01') returning id into v_id;
  if (select number from public.invoices where id = v_id) is not null then
    raise exception 'a draft got a number';
  end if;
  update public.invoices set status = 'sent' where id = v_id returning number into v_number;
  if v_number <> 'INV-2025-0001' then
    raise exception 'numbered %', v_number;
  end if;
  insert into public.invoices (organization_id, status, issued_on) values ('${ALICE}', 'sent', '2024-12-31') returning number into v_number;
  if v_number <> 'INV-2024-0001' then
    raise exception 'numbered %', v_number;
  end if;
  insert into public.invoices (organization_id, status, issued_on) values ('${ALICE}', 'sent', '2025-03-02') returning number into v_number;
  if v_number <> 'INV-2025-0002' then
    raise exception 'numbered %', v_number;
  end if;
  insert into public.invoices (organization_id, status) values ('${ALICE}', 'sent') returning number into v_number;
  if v_number <> 'INV-' || ${YEAR} || '-0001' and ${YEAR} not in ('2024', '2025') then
    raise exception 'numbered % without an issue date', v_number;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("syncs a date column's period in UTC", async () => {
    await expect(
      issued(`set timezone = 'Europe/Amsterdam';
alter table public.invoices disable trigger user;
insert into public.invoices (organization_id, number, status, issued_on) values
  ('${ALICE}', 'INV-2025-0009', 'sent', '2025-01-01');
alter table public.invoices enable trigger user;
do $$
declare
  v_number text;
begin
  perform better_supabase.sync_number_sequences();
  insert into public.invoices (organization_id, status, issued_on) values ('${ALICE}', 'sent', '2025-01-01') returning number into v_number;
  if v_number <> 'INV-2025-0010' then
    raise exception 'numbered %', v_number;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});

const CAROL = "33333333-3333-4333-8333-333333333333";

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

const ORGANIZATIONS = `
insert into public.organizations (id, invoice_number_format) values
  ('${ALICE}', '{yyyy}-{n:3}'),
  ('${BOB}', null),
  ('${CAROL}', 'F{yy}{mm}-{n}');
`;

const perTenant = {
  period: "format",
  format: "{n}",
  formatFrom: { column: "public.organizations.invoice_number_format" },
  table: "public.invoices",
  column: "formatted_number",
  tenantColumn: "organization_id",
  periodColumn: "issued_on",
  assignOn: "new.status = 'sent'",
};

const tenantFormats = (
  check: string,
  entity: Record<string, unknown> = {},
): Promise<void> =>
  withNumbers({ invoice: { ...perTenant, ...entity } }, TENANT_FORMATS, [
    ORGANIZATIONS,
    check,
  ]);

const send = (tenant: string, issued: string, expected: string): string =>
  `  insert into public.invoices (organization_id, status, issued_on) values ('${tenant}', 'sent', '${issued}') returning formatted_number into v_number;
  if v_number is distinct from '${expected}' then
    raise exception 'numbered % for ${tenant} on ${issued}, expected ${expected}', v_number;
  end if;`;

describe("per-tenant formats", () => {
  it("resolves the tenant's format and derives the period from it", () => {
    const sql = sqlOf({
      "number-sequences": {
        options: {
          entities: {
            invoice: { ...perTenant, sequenceColumn: "number" },
            ticket: { period: "format", format: "T-{yyyy}-{mm}-{n}" },
          },
        },
      },
    });

    expect(sql).toContain(
      `when 'invoice' then coalesce((select nullif(btrim(s."invoice_number_format"), '') from "public"."organizations" s where s."id" = p_tenant), '{n}')`,
    );
    expect(sql).toContain(
      `when 'invoice' then better_supabase.number_format_period("better_supabase"."number_format"(next_number.tenant, 'invoice'), next_number.at)`,
    );
    expect(sql).toContain(
      "when 'ticket' then to_char(next_number.at at time zone 'utc', 'YYYY-MM')",
    );
    expect(sql).toContain('new."number" := v_n;');
    expect(sql).toContain('or new."number" is distinct from old."number"');
    expect(sql).toContain(
      'elsif new."number" is distinct from old."number" then',
    );
    expect(sql).toContain("NUMBER_FORMAT_INVALID");
  });

  it("checks an entity's own permission in preview_number", () => {
    const sql = sqlOf({
      "number-sequences": {
        permissions: { assign: "documents.number" },
        options: {
          entities: {
            invoice: { ...perTenant, permission: "invoices.write" },
            quote: { period: "year", format: "Q-{n}" },
          },
        },
      },
    });

    expect(sql).toContain(
      "coalesce(better_supabase.can('tenant', p_tenant, case p_entity\n    when 'invoice' then 'invoices.write'\n    else 'documents.number'\n  end), false)",
    );
  });

  it.each([
    ["a formatFrom that is not an object", { formatFrom: "x" }, /formatFrom/],
    [
      "a formatFrom column without a schema",
      { formatFrom: { column: "organizations.format" } },
      /schema\.table\.column/,
    ],
    [
      "a formatFrom key that is not a name",
      { formatFrom: { column: "public.o.f", key: "Id" } },
      /formatFrom\.key/,
    ],
    ["an empty permission", { permission: "" }, /permission must be/],
    [
      "a sequenceColumn equal to column",
      { sequenceColumn: "formatted_number" },
      /sequenceColumn/,
    ],
  ])("refuses %s", (_label, entity, message) => {
    expect(() =>
      sqlOf({
        "number-sequences": {
          options: { entities: { invoice: { ...perTenant, ...entity } } },
        },
      }),
    ).toThrow(message);
  });
});

describe("per-tenant formats in PGlite", BOOT, () => {
  it("numbers continuously, yearly or monthly by each tenant's format", async () => {
    await expect(
      tenantFormats(
        `do $$
declare
  v_number text;
begin
${send(ALICE, "2025-12-31", "2025-001")}
${send(ALICE, "2026-01-02", "2026-001")}
${send(ALICE, "2026-02-03", "2026-002")}
${send(BOB, "2025-12-31", "1")}
${send(BOB, "2026-01-02", "2")}
${send(CAROL, "2026-01-05", "F2601-1")}
${send(CAROL, "2026-02-01", "F2602-1")}
${send(CAROL, "2026-02-09", "F2602-2")}
  if (select number from public.invoices where formatted_number = 'F2602-2') <> 2 then
    raise exception 'the sequence column holds the wrong number';
  end if;
end;
$$;`,
        { sequenceColumn: "number" },
      ),
    ).resolves.toBeUndefined();
  });

  it("keeps the number and its sequence immutable", async () => {
    await expect(
      tenantFormats(
        `insert into public.invoices (organization_id, status, issued_on) values ('${ALICE}', 'sent', '2026-01-02');
update public.invoices set number = 7;`,
        { sequenceColumn: "number" },
      ),
    ).rejects.toThrow(/a number cannot change/);
  });

  it("refuses a client that writes the sequence column", async () => {
    const asClient = (sql: string): string =>
      `select set_config('request.jwt.claims', '{"role":"authenticated"}', false);
${sql}`;

    await expect(
      tenantFormats(
        asClient(
          `insert into public.invoices (organization_id, number) values ('${ALICE}', 7);`,
        ),
        { sequenceColumn: "number" },
      ),
    ).rejects.toThrow(/not set by hand/);
    await expect(
      tenantFormats(
        `insert into public.invoices (organization_id) values ('${ALICE}');
${asClient("update public.invoices set number = 7;")}`,
        { sequenceColumn: "number" },
      ),
    ).rejects.toThrow(/not set by hand/);
    await expect(
      tenantFormats(
        `insert into public.invoices (organization_id) values ('${ALICE}');
${asClient(`do $$
declare
  v_number bigint;
begin
  update public.invoices set issued_on = '2026-01-02';
  update public.invoices set status = 'sent' returning number into v_number;
  if v_number <> 1 then
    raise exception 'numbered %', v_number;
  end if;
end;
$$;`)}`,
        { sequenceColumn: "number" },
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses a tenant format without {n}", async () => {
    await expect(
      tenantFormats(
        `update public.organizations set invoice_number_format = 'INV-{yyyy}' where id = '${ALICE}';
insert into public.invoices (organization_id, status, issued_on) values ('${ALICE}', 'sent', '2026-01-02');`,
      ),
    ).rejects.toThrow(/has no \{n\}/);
  });

  it("syncs per tenant from the sequence column or the tenant's format", async () => {
    const seeded = `alter table public.invoices disable trigger user;
update public.organizations set invoice_number_format = 'INV/{yyyy}.{n:4} (x)' where id = '${CAROL}';
insert into public.invoices (organization_id, status, issued_on, number, formatted_number) values
  ('${ALICE}', 'sent', '2026-03-01', 41, '2026-041'),
  ('${ALICE}', 'sent', '2025-03-01', 9, '2025-009'),
  ('${BOB}', 'sent', '2024-03-01', 17, '17'),
  ('${CAROL}', 'sent', '2026-03-01', 5, 'INV/2026.0005 (x)');
alter table public.invoices enable trigger user;
do $$
declare
  v_number text;
begin
  perform better_supabase.sync_number_sequences();
${send(ALICE, "2026-04-01", "2026-042")}
${send(ALICE, "2025-04-01", "2025-010")}
${send(BOB, "2026-04-01", "18")}
${send(CAROL, "2026-04-01", "INV/2026.0006 (x)")}
end;
$$;`;

    await expect(
      tenantFormats(seeded, { sequenceColumn: "number" }),
    ).resolves.toBeUndefined();
    await expect(tenantFormats(seeded)).resolves.toBeUndefined();
  });

  it("refuses to sync a per-tenant period without periodColumn", async () => {
    await expect(
      tenantFormats("select better_supabase.sync_number_sequences();", {
        periodColumn: undefined,
      }),
    ).rejects.toThrow(/chosen per tenant; set options/);
  });
});

const RESETS = `update public.organizations set invoice_number_format = 'INV-{yyyy}{mm}-{n}', invoice_number_reset = 'year' where id = '${ALICE}';
update public.organizations set invoice_number_format = '{yyyy}-{n}', invoice_number_reset = 'none' where id = '${BOB}';`;

const resets = (
  check: string,
  entity: Record<string, unknown> = {},
): Promise<void> =>
  tenantFormats(`${RESETS}\n${check}`, {
    periodFrom: { column: "public.organizations.invoice_number_reset" },
    ...entity,
  });

describe("per-tenant periods", () => {
  it("chooses the period from the tenant's column before the format", () => {
    const sql = sqlOf({
      "number-sequences": {
        options: {
          entities: {
            invoice: {
              ...perTenant,
              periodFrom: {
                column: "public.organizations.invoice_number_reset",
              },
            },
          },
        },
      },
    });

    expect(sql).toContain(
      `when 'invoice' then (select nullif(btrim(s."invoice_number_reset"::text), '') from "public"."organizations" s where s."id" = p_tenant)`,
    );
    expect(sql).toContain(
      `when 'invoice' then case "better_supabase"."number_period"(next_number.tenant, 'invoice')`,
    );
    expect(sql).toContain("NUMBER_PERIOD_INVALID");
    expect(sql).toContain(
      'grant execute on function "better_supabase"."number_period"(uuid, text) to service_role;',
    );
  });

  it("re-syncs from a tenant trigger when the tenant's period changes", () => {
    const sql = sqlOf({
      "number-sequences": {
        options: {
          entities: {
            invoice: {
              ...perTenant,
              periodFrom: {
                column: "public.organizations.invoice_number_reset",
              },
            },
          },
        },
      },
    });

    expect(sql).toContain(
      `if better_supabase.number_period_kind(coalesce(nullif(btrim(old."invoice_number_reset"::text), ''), 'format'), coalesce(nullif(btrim(old."invoice_number_format"::text), ''), '{n}')) is distinct from better_supabase.number_period_kind(coalesce(nullif(btrim(new."invoice_number_reset"::text), ''), 'format'), coalesce(nullif(btrim(new."invoice_number_format"::text), ''), '{n}')) then
    perform "better_supabase"."sync_number_sequences"(new."id", 'invoice');`,
    );
    expect(sql).toContain(
      `create trigger "bsb_sync_number_period_invoice" after update on "public"."organizations"`,
    );
    expect(sql).toContain(
      `revoke execute on function better_supabase."bsb_sync_number_period_invoice"() from public, anon, authenticated;`,
    );
  });

  it("adds a trigger per tenant table and none when the period cannot change or sync", () => {
    const render = (entity: Record<string, unknown>): string =>
      sqlOf({
        "number-sequences": {
          options: { entities: { invoice: { ...perTenant, ...entity } } },
        },
      });

    const split = render({
      periodFrom: { column: "public.settings.invoice_reset", key: "org_id" },
    });

    expect(split).toContain(
      `create trigger "bsb_sync_number_period_invoice" after update on "public"."settings"`,
    );
    expect(split).toContain(
      `create trigger "bsb_sync_number_period_invoice_format" after update on "public"."organizations"`,
    );
    expect(split).toContain(
      `coalesce((select nullif(btrim(s."invoice_reset"::text), '') from "public"."settings" s where s."org_id" = new."id"), 'format')`,
    );
    expect(render({})).toContain("bsb_sync_number_period_invoice");
    expect(render({ period: "year" })).not.toContain(
      "bsb_sync_number_period_invoice",
    );
    expect(
      render({
        periodFrom: { column: "public.organizations.invoice_number_reset" },
        periodColumn: undefined,
      }),
    ).not.toContain("bsb_sync_number_period_invoice");
  });

  it("refuses a periodFrom that is not a tenant column", () => {
    expect(() =>
      sqlOf({
        "number-sequences": {
          options: {
            entities: {
              invoice: { ...perTenant, periodFrom: { column: "reset" } },
            },
          },
        },
      }),
    ).toThrow(/periodFrom\.column must be/);
  });
});

describe("per-tenant periods in PGlite", BOOT, () => {
  it("resets yearly, never or by the format, as each tenant chose", async () => {
    await expect(
      resets(`do $$
declare
  v_number text;
begin
${send(ALICE, "2026-01-05", "INV-202601-1")}
${send(ALICE, "2026-02-01", "INV-202602-2")}
${send(ALICE, "2027-01-03", "INV-202701-1")}
${send(BOB, "2025-12-31", "2025-1")}
${send(BOB, "2026-01-02", "2026-2")}
${send(CAROL, "2026-01-05", "F2601-1")}
${send(CAROL, "2026-02-01", "F2602-1")}
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("previews in the tenant's period", async () => {
    await expect(
      resets(`insert into public.invoices (organization_id, status, issued_on) values ('${ALICE}', 'sent', '2026-01-05');
do $$
begin
  if better_supabase.preview_number('${ALICE}', 'invoice', '2026-03-15') <> 'INV-202603-2' then
    raise exception 'previewed %', better_supabase.preview_number('${ALICE}', 'invoice', '2026-03-15');
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a period the module does not know", async () => {
    await expect(
      resets(`update public.organizations set invoice_number_reset = 'weekly' where id = '${CAROL}';
insert into public.invoices (organization_id, status, issued_on) values ('${CAROL}', 'sent', '2026-01-02');`),
    ).rejects.toThrow(/must be none, year, month or format/);
  });

  it("syncs each tenant in its own period", async () => {
    await expect(
      resets(
        `alter table public.invoices disable trigger user;
insert into public.invoices (organization_id, status, issued_on, number, formatted_number) values
  ('${ALICE}', 'sent', '2026-01-05', 1, 'INV-202601-1'),
  ('${ALICE}', 'sent', '2026-02-01', 2, 'INV-202602-2'),
  ('${BOB}', 'sent', '2025-02-01', 7, '2025-7'),
  ('${CAROL}', 'sent', '2026-02-01', 4, 'F2602-4');
alter table public.invoices enable trigger user;
do $$
declare
  v_number text;
begin
  perform better_supabase.sync_number_sequences();
${send(ALICE, "2026-03-01", "INV-202603-3")}
${send(BOB, "2026-03-01", "2026-8")}
${send(CAROL, "2026-02-09", "F2602-5")}
end;
$$;`,
        { sequenceColumn: "number" },
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses to sync a per-tenant period without periodColumn", async () => {
    await expect(
      resets("select better_supabase.sync_number_sequences();", {
        periodColumn: undefined,
      }),
    ).rejects.toThrow(/period is chosen per tenant/);
  });
});

const GENERATED_PERIOD = `${TENANT_FORMATS}
alter table public.organizations
  add column invoice_number_period text generated always as (
    case invoice_number_reset when 'never' then 'none' when 'yearly' then 'year' end
  ) stored;
`;

describe("tenant period changes in PGlite", BOOT, () => {
  it("re-syncs the counters when a tenant's period changes, so no number repeats", async () => {
    await expect(
      resets(
        `update public.organizations set invoice_number_format = 'INV-{n}', invoice_number_reset = 'year' where id = '${ALICE}';
do $$
declare
  v_number text;
begin
${send(ALICE, "2026-01-05", "INV-1")}
${send(ALICE, "2026-02-01", "INV-2")}
  update public.organizations set invoice_number_reset = 'none' where id = '${ALICE}';
${send(ALICE, "2026-03-01", "INV-3")}
  update public.organizations set invoice_number_reset = 'year' where id = '${ALICE}';
${send(ALICE, "2026-04-01", "INV-4")}
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("re-syncs when a tenant's format moves its period", async () => {
    await expect(
      tenantFormats(
        `do $$
declare
  v_number text;
begin
${send(ALICE, "2026-01-05", "2026-001")}
${send(ALICE, "2026-02-01", "2026-002")}
  update public.organizations set invoice_number_format = 'A{n:4}' where id = '${ALICE}';
${send(ALICE, "2026-03-01", "A0003")}
end;
$$;`,
        { sequenceColumn: "number" },
      ),
    ).resolves.toBeUndefined();
  });

  it("leaves the counters alone on an update that keeps the period", async () => {
    await expect(
      resets(
        `alter table public.organizations add column name text;
update public.organizations set invoice_number_format = 'INV-{n}', invoice_number_reset = 'none' where id = '${ALICE}';
alter table public.invoices disable trigger user;
insert into public.invoices (organization_id, status, issued_on, formatted_number) values
  ('${ALICE}', 'sent', '2026-01-05', 'INV-50');
alter table public.invoices enable trigger user;
update public.organizations set name = 'Alice' where id = '${ALICE}';
update public.organizations set invoice_number_format = 'NR-{n}', invoice_number_reset = '' where id = '${BOB}';
update public.organizations set invoice_number_format = 'INV-{n:2}' where id = '${ALICE}';
do $$
declare
  v_number text;
begin
${send(ALICE, "2026-02-01", "INV-01")}
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("follows a generated period column", async () => {
    await expect(
      withNumbers(
        {
          invoice: {
            ...perTenant,
            periodFrom: {
              column: "public.organizations.invoice_number_period",
            },
          },
        },
        GENERATED_PERIOD,
        [
          ORGANIZATIONS,
          `update public.organizations set invoice_number_format = 'INV-{n}', invoice_number_reset = 'yearly' where id = '${ALICE}';
do $$
declare
  v_number text;
begin
${send(ALICE, "2026-01-05", "INV-1")}
${send(ALICE, "2026-02-01", "INV-2")}
  update public.organizations set invoice_number_reset = 'never' where id = '${ALICE}';
${send(ALICE, "2026-03-01", "INV-3")}
end;
$$;`,
        ],
      ),
    ).resolves.toBeUndefined();
  });
});

const CAN = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean
language sql
stable
as $$ select scope_id = '${ALICE}' and permission = 'invoices.write' $$;
`;

const asMember = (check: string): string =>
  `select set_config('request.jwt.claims', '{"role":"authenticated"}', false);
${check}`;

const previews = (check: string): Promise<void> =>
  withNumbers(
    { invoice: { ...perTenant, sequenceColumn: "number" } },
    TENANT_FORMATS,
    [ORGANIZATIONS, CAN, check],
    { permissions: { assign: "invoices.write" } },
  );

const entityPreviews = (check: string): Promise<void> =>
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

describe("preview_number", BOOT, () => {
  it("previews the tenant's next number under the assign permission", async () => {
    await expect(
      previews(`insert into public.invoices (organization_id, status, issued_on) values ('${ALICE}', 'sent', '2026-01-02');
${asMember(`do $$
begin
  if better_supabase.preview_number('${ALICE}', 'invoice', '2026-05-01') <> '2026-002' then
    raise exception 'previewed %', better_supabase.preview_number('${ALICE}', 'invoice', '2026-05-01');
  end if;
  if better_supabase.preview_number('${ALICE}', 'invoice', '2027-05-01') <> '2027-001' then
    raise exception 'previewed % for a new year', better_supabase.preview_number('${ALICE}', 'invoice', '2027-05-01');
  end if;
  if better_supabase.preview_number('${ALICE}', 'invoice', '2026-05-01') <> '2026-002' then
    raise exception 'a preview took the number';
  end if;
end;
$$;`)}`),
    ).resolves.toBeUndefined();
  });

  it("refuses a caller without the assign permission", async () => {
    await expect(
      previews(
        asMember(`select better_supabase.preview_number('${BOB}', 'invoice');`),
      ),
    ).rejects.toThrow(/not allowed to number documents/);
  });

  it("checks an entity's own permission and the block key for the others", async () => {
    await expect(
      entityPreviews(
        asMember(`do $$
begin
  if better_supabase.preview_number('${ALICE}', 'invoice', '2026-05-01') <> '2026-001' then
    raise exception 'previewed %', better_supabase.preview_number('${ALICE}', 'invoice', '2026-05-01');
  end if;
end;
$$;`),
      ),
    ).resolves.toBeUndefined();
    await expect(
      entityPreviews(
        asMember(`select better_supabase.preview_number('${ALICE}', 'quote');`),
      ),
    ).rejects.toThrow(/not allowed to number documents/);
  });
});
