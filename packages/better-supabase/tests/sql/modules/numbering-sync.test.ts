import { describe, expect, it } from "vitest";

import {
  ALICE,
  BOB,
  BOOT,
  CAROL,
  ISSUED,
  issued,
  withInvoices,
  withNumbers,
  YEAR,
} from "../../fixtures/numbering.ts";

describe("sync_number_sequences", BOOT, () => {
  it("numbers past the seeded rows after a sync, per tenant and period", async () => {
    await expect(
      withInvoices(`do $$
declare
  v_synced integer;
  v_number text;
begin
  v_synced := (better_supabase.sync_number_sequences() ->> 'synced')::integer;
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

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);`;

const IMPORTING = `${SERVICE}
  perform set_config('better_supabase.import_run', '99999999-9999-4999-8999-999999999999', true);`;

describe("fixed numbers and the sync report", BOOT, () => {
  it("accepts a historical number only while an import runs", async () => {
    await expect(
      withInvoices(`do $$
begin
  ${SERVICE}
  perform better_supabase.set_fixed_number('invoice', 'INV-2023-0365');
end;
$$;`),
    ).rejects.toThrow(/only accepted during an import/);
  });

  it("raises the counter to an imported number and continues above it", async () => {
    await expect(
      withInvoices(`do $$
declare
  v_number text;
begin
  ${IMPORTING}
  insert into public.invoices (organization_id, number)
    values ('${CAROL}', 'INV-' || ${YEAR} || '-0365');
  insert into public.invoices (organization_id) values ('${CAROL}') returning number into v_number;
  if v_number <> 'INV-' || ${YEAR} || '-0366' then
    raise exception 'numbered %', v_number;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a hand-set number from a client even in import mode", async () => {
    await expect(
      withInvoices(`do $$
begin
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  perform set_config('better_supabase.import_run', '99999999-9999-4999-8999-999999999999', true);
  insert into public.invoices (organization_id, number) values ('${CAROL}', 'INV-1');
end;
$$;`),
    ).rejects.toThrow(/assigned by the sequence/);
  });

  it("lists the numbers that don't match the format without rejecting them", async () => {
    await expect(
      withInvoices(`do $$
declare
  v_report jsonb;
begin
  v_report := better_supabase.sync_number_sequences('${BOB}', 'invoice');
  if (v_report ->> 'synced')::int <> 1 then
    raise exception 'synced %', v_report;
  end if;
  if v_report -> 'mismatched' <> '[{"scope": "", "entity": "invoice", "number": "imported-without-format"}]'::jsonb then
    raise exception 'mismatched %', v_report;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
