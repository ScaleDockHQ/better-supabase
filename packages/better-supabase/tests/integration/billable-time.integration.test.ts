import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createBillableTime } from "../../src/blocks/billable-time/index.ts";
import { createContacts } from "../../src/blocks/contacts/index.ts";
import { createInvoices } from "../../src/blocks/invoices/index.ts";
import {
  createTimeTracking,
  sqlTransport,
} from "../../src/blocks/time-tracking/index.ts";
import { money } from "../../src/commerce/money.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "subjects",
  "relations",
  "contacts",
  "approvals",
  "time-tracking",
  "invoices",
  "billable-time",
];

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["contacts"], {}),
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const at = (text: string): Temporal.Instant => Temporal.Instant.from(text);

describe.skipIf(!live)("billable-time", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("bills unbilled time at the rate card on a draft invoice and releases it on void", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const ada = await s.user("ada");
      await s.install(MODULES, layout);
      const tenant = await s.organization(owner, { member: ada });
      const transport = sqlTransport(s.sql);
      const billing = createBillableTime({ transport, tenant });
      const time = createTimeTracking({ transport, tenant });
      const invoices = createInvoices({ transport });

      await s.as(owner);

      const acme = await createContacts({ transport })
        .saveCompany(tenant, { name: "Acme" })
        .orThrow();

      const company = { type: "company", id: acme.id };

      await billing
        .setRate({
          rate: money(10_000n, "EUR"),
          effectiveFrom: Temporal.PlainDate.from("2026-01-01"),
        })
        .orThrow();
      await billing
        .setRate({
          rate: money(12_000n, "EUR"),
          userId: ada.id,
          subject: company,
          effectiveFrom: Temporal.PlainDate.from("2026-01-01"),
        })
        .orThrow();

      await s.as(ada);

      const workshop = await time
        .log({
          startedAt: at("2026-10-06T09:00:00Z"),
          endedAt: at("2026-10-06T10:30:00Z"),
          subject: company,
          billable: true,
        })
        .orThrow();

      await time
        .log({
          startedAt: at("2026-10-06T13:00:00Z"),
          endedAt: at("2026-10-06T14:00:00Z"),
          subject: company,
          billable: true,
          rate: money(9000n, "USD"),
        })
        .orThrow();

      expect(await billing.unbilled().then(hint)).toBe(
        "BILLABLE_TIME_FORBIDDEN",
      );

      await s.as(owner);

      expect(
        (await billing.rateFor({ userId: ada.id, subject: company }).orThrow())
          ?.rate,
      ).toEqual(money(12_000n, "EUR"));

      const preview = await billing
        .unbilled({ subject: company, groupBy: "entry" })
        .orThrow();

      expect(preview.totals).toEqual([
        money(18_000n, "EUR"),
        money(9000n, "USD"),
      ]);
      expect(preview.unrated).toEqual([]);
      expect(await billing.invoice({ subject: company }).then(hint)).toBe(
        "BILLABLE_TIME_CURRENCIES",
      );

      const invoice = await billing
        .invoice({ subject: company, currency: "EUR", title: "October" })
        .orThrow();

      expect(invoice.total).toEqual(money(18_000n, "EUR"));
      expect(invoice.entryIds).toEqual([workshop.id]);

      expect(
        await time
          .update(workshop.id, { endedAt: at("2026-10-06T11:00:00Z") })
          .then(hint),
      ).toBe("TIME_ENTRY_INVOICED");
      expect(
        (await billing.invoicedEntries(invoice.invoiceId).orThrow()).map(
          (entry) => entry.seconds,
        ),
      ).toEqual([5400]);

      await s.client.query("reset role");

      expect(
        await s.rows<{ status: string; quantity: string; unit: string }>(
          `select i.status, l.quantity::text as quantity, l.unit_amount::text as unit
           from better_supabase.invoices i join better_supabase.invoice_lines l on l.parent_id = i.id
           where i.id = $1`,
          [invoice.invoiceId],
        ),
      ).toEqual([{ status: "draft", quantity: "1.5000", unit: "12000" }]);
      expect(
        await s.rows<{ type: string }>(
          "select type from better_supabase.outbox_events where organization_id = $1 and type = 'time_entry.invoiced'",
          [tenant],
        ),
      ).toHaveLength(1);

      await s.as(owner);
      await invoices.void(invoice.invoiceId, "wrong client").orThrow();

      expect(
        (await billing.unbilled({ subject: company }).orThrow()).totals,
      ).toEqual([money(18_000n, "EUR"), money(9000n, "USD")]);
    } finally {
      await s.close();
    }
  });

  it("purges an organization with invoiced time", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      await s.install([...MODULES, "data-lifecycle"], layout);
      const tenant = await s.organization(owner);
      const transport = sqlTransport(s.sql);
      const billing = createBillableTime({ transport, tenant });

      await s.as(owner);
      await billing
        .setRate({
          rate: money(10_000n, "EUR"),
          effectiveFrom: Temporal.PlainDate.from("2026-01-01"),
        })
        .orThrow();
      await createTimeTracking({ transport, tenant })
        .log({
          startedAt: at("2026-10-06T09:00:00Z"),
          endedAt: at("2026-10-06T10:00:00Z"),
          billable: true,
        })
        .orThrow();
      await billing.invoice().orThrow();

      await s.client.query("reset role");
      await s.rows(
        "insert into better_supabase.organization_deletions (organization_id, purge_after) values ($1, now() - interval '1 minute')",
        [tenant],
      );
      await s.service();

      const purged = await s.value<{ deleted: Record<string, number> }>(
        "better_supabase.purge_organization($1)",
        [tenant],
      );

      expect(purged.deleted).toMatchObject({
        "better_supabase.time_entries": 1,
        "better_supabase.time_invoice_entries": 1,
        "better_supabase.time_rates": 1,
      });
    } finally {
      await s.close();
    }
  });
});
