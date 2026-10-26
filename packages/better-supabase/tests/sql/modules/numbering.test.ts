import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { perTenant } from "../../fixtures/numbering.ts";

const sqlOf = (modules: AnyBlocksConfig = {}): string =>
  renderBlocks(["numbering"], { modules })
    .filter((file) => file.module === "numbering")
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
      numbering: {
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

  it("takes the tenant column of a numbered table from config.subjects", () => {
    const entities = {
      invoice: {
        period: "none",
        format: "{n}",
        table: "public.invoices",
        column: "number",
      },
    };

    const render = (subjects = {}): string =>
      renderBlocks(["numbering"], {
        modules: { numbering: { options: { entities } } },
        subjects,
      })
        .filter((file) => file.module === "numbering")
        .map((file) => file.contents)
        .join("\n");

    expect(render()).toContain('new."organization_id"');
    expect(
      render({ invoice: { table: "invoices", tenant: "org_id" } }),
    ).toContain('new."org_id"');
  });

  it("refuses a predicate that is not an expression", () => {
    expect(() =>
      sqlOf({
        numbering: {
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
      numbering: {
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
      numbering: {
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
      numbering: {
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
    expect(() => sqlOf({ numbering: { options: { entities } } })).toThrow(
      message,
    );
  });

  it("refuses a periodColumn that is not a column name", () => {
    expect(() =>
      sqlOf({
        numbering: {
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

describe("per-tenant formats", () => {
  it("resolves the tenant's format and derives the period from it", () => {
    const sql = sqlOf({
      numbering: {
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
      numbering: {
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
        numbering: {
          options: { entities: { invoice: { ...perTenant, ...entity } } },
        },
      }),
    ).toThrow(message);
  });
});

describe("per-tenant periods", () => {
  it("chooses the period from the tenant's column before the format", () => {
    const sql = sqlOf({
      numbering: {
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
      numbering: {
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
        numbering: {
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
        numbering: {
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
