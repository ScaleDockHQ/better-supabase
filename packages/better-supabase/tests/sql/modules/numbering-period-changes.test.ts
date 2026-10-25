import { describe, expect, it } from "vitest";

import {
  ALICE,
  BOB,
  BOOT,
  GENERATED_PERIOD,
  ORGANIZATIONS,
  perTenant,
  resets,
  send,
  tenantFormats,
  withNumbers,
} from "../../fixtures/numbering.ts";

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
