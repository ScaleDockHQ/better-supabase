import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderModules } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const sqlOf = (modules: AnyBlocksConfig = {}): string =>
  renderModules(["number-sequences"], { modules })
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
    expect(sql).not.toContain("to authenticated, service_role");
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
      "to_char(t.\"issued_at\" at time zone 'utc', 'YYYY-MM')",
    );
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

async function withInvoices(check: string): Promise<void> {
  const files = renderModules(["number-sequences"], {
    modules: {
      "number-sequences": {
        options: {
          entities: {
            invoice: {
              period: "year",
              format: "INV-{yyyy}-{n:4}",
              table: "public.invoices",
              column: "number",
              tenantColumn: "organization_id",
            },
          },
        },
      },
    },
  });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      INVOICES,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      SEEDED,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

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
