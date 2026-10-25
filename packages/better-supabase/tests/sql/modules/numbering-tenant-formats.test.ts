import { describe, expect, it } from "vitest";

import {
  ALICE,
  BOB,
  BOOT,
  CAROL,
  send,
  tenantFormats,
} from "../../fixtures/numbering.ts";

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
