import { describe, expect, it } from "vitest";

import {
  ALICE,
  BOB,
  BOOT,
  CAROL,
  resets,
  send,
} from "../../fixtures/numbering.ts";

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
