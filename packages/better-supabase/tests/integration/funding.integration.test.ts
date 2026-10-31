import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createFunding } from "../../src/blocks/funding/index.ts";
import { createTimeTracking } from "../../src/blocks/time-tracking/index.ts";
import { money } from "../../src/commerce/money.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const TABLES = `create schema funding_it;
create table funding_it.clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text not null
);
alter table funding_it.clients enable row level security;
create policy clients_read on funding_it.clients for select to authenticated using (true);
grant usage on schema funding_it to authenticated;
grant select on funding_it.clients to authenticated;`;

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "approvals",
  "time-tracking",
  "numbering",
  "invoices",
  "contacts",
  "funding",
];

const LAYOUT: BlockSqlLayout = {
  subjects: {
    ...withBlockSubjects({}, ["contacts"], {}),
    client: { table: "funding_it.clients", idType: "uuid" },
  },
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const day = (text: string): Temporal.PlainDate => Temporal.PlainDate.from(text);
const at = (text: string): Temporal.Instant => Temporal.Instant.from(text);

describe.skipIf(!live)("funding", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("awards units, registers care from time, claims it and invoices the funder", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(TABLES);
      const owner = await s.user("owner");
      const carer = await s.user("carer");
      const outsider = await s.user("outsider");
      await s.install(MODULES, LAYOUT);

      const org = await s.organization(owner, { member: carer });

      const [client, unfunded] = await s.rows<{ id: string }>(
        "insert into funding_it.clients (organization_id, name) values ($1, 'Ada'), ($1, 'Bea') returning id",
        [org],
      );

      const [funder] = await s.rows<{ id: string }>(
        "insert into better_supabase.companies (tenant_id, name, lifecycle, roles) values ($1, 'Zorgkantoor', 'customer', '{funder}') returning id",
        [org],
      );

      const subject = { type: "client", id: client?.id ?? "" };
      const funderId = funder?.id ?? "";

      const funding = createFunding({ transport: sqlTransport(s.sql) });

      await s.as(owner);

      const product = await funding
        .saveProduct(org, {
          code: "H300",
          title: "Individual support",
          unit: "hour",
          rate: money(6850n, "EUR"),
        })
        .orThrow();

      const award = await funding
        .createAward(org, subject, {
          funderId,
          productId: product.id,
          units: 2,
          period: "week",
          startsOn: day("2026-10-05"),
          reference: "WLZ-1",
        })
        .orThrow();

      expect(award).toMatchObject({ status: "active", subject, units: 2 });

      const time = createTimeTracking({
        transport: sqlTransport(s.sql),
        tenant: org,
      });

      await s.as(carer);

      await time
        .log({
          startedAt: at("2026-10-06T09:00:00Z"),
          endedAt: at("2026-10-06T10:30:00Z"),
          subject,
        })
        .orThrow();
      await time
        .log({
          startedAt: at("2026-10-07T09:00:00Z"),
          endedAt: at("2026-10-07T10:00:00Z"),
          subject: { type: "client", id: unfunded?.id ?? "" },
        })
        .orThrow();

      const sheet = await time.submit(day("2026-10-05")).orThrow();

      await s.as(owner);
      await s.value("better_supabase.decide_approval($1, 'approved')", [
        sheet.approvalId,
      ]);

      await s.asRole(carer);
      expect(
        await funding
          .registerFromTime(org, day("2026-10-05"), day("2026-10-11"))
          .then((result) => (result.ok ? "ok" : result.error.code)),
      ).toBe("42501");

      await s.service();

      const run = await funding
        .registerFromTime(org, day("2026-10-05"), day("2026-10-11"))
        .orThrow();

      expect(run.registered).toHaveLength(1);
      expect(run.registered[0]).toMatchObject({
        sourceType: "time_entry",
        units: 1.5,
      });
      expect(run.unmatched).toEqual([
        expect.objectContaining({ reason: "no_award" }),
      ]);
      expect(
        (
          await funding
            .registerFromTime(org, day("2026-10-05"), day("2026-10-11"))
            .orThrow()
        ).registered,
      ).toEqual([]);

      await s.as(carer);

      const visit = await funding
        .registerDelivery(award.id, {
          deliveredOn: day("2026-10-08"),
          units: 1,
          note: "Evening visit",
        })
        .orThrow();

      expect(await funding.approveDeliveries([visit.id]).then(hint)).toBe(
        "FUNDING_FORBIDDEN",
      );

      await s.as(owner);

      const usage = await funding.usage(award.id).orThrow();

      expect(usage.periods[0]).toMatchObject({
        awarded: 2,
        used: 2.5,
        over: 0.5,
      });

      expect(
        await funding
          .approveDeliveries([visit.id, run.registered[0]?.id ?? ""])
          .orThrow(),
      ).toBe(2);

      const claim = await funding
        .buildClaim(org, {
          funderId,
          periodStart: day("2026-10-01"),
          periodEnd: day("2026-10-31"),
          format: "test",
        })
        .orThrow();

      expect(claim.status).toBe("draft");
      expect(claim.total).toEqual(money(17_125n, "EUR"));
      expect(claim.lines.length).toBeGreaterThan(0);

      const sent = createFunding({
        transport: sqlTransport(s.sql),
        formats: [
          {
            apiVersion: 1,
            key: "test",
            render: (rendered, lines) => ({
              body: `${rendered.number};${lines.length}`,
              filename: `${rendered.number}.txt`,
              contentType: "text/plain",
            }),
            parseResponse: (body) => ({
              lines: [
                { lineId: body, status: "rejected", rejectionCode: "8001" },
              ],
            }),
          },
        ],
        channel: {
          apiVersion: 1,
          key: "inbox",
          send: () => Promise.resolve({ externalRef: "VZ-77" }),
          poll: () => Promise.resolve(claim.lines[0]?.id),
        },
      });

      expect(await sent.send(claim.id).orThrow()).toMatchObject({
        status: "sent",
        externalRef: "VZ-77",
      });

      const answered = await sent.poll(claim.id).orThrow();

      expect(answered).toMatchObject({ status: "rejected" });
      expect(answered?.lines[0]).toMatchObject({
        status: "rejected",
        rejectionCode: "8001",
      });
      expect(
        await funding.deliveries(org, { status: "approved" }).orThrow(),
      ).toHaveLength(2);
      expect(await funding.invoiceClaim(claim.id).then(hint)).toBe(
        "FUNDING_CLAIM_STATUS_INVALID",
      );

      const second = await funding
        .buildClaim(org, {
          funderId,
          periodStart: day("2026-10-01"),
          periodEnd: day("2026-10-31"),
          format: "test",
        })
        .orThrow();

      await funding.markSent(second.id, { externalRef: "VZ-78" }).orThrow();
      await funding.recordResponse(second.id, { lines: [] }).orThrow();

      const invoiced = await funding.invoiceClaim(second.id).orThrow();

      expect(invoiced.claim.status).toBe("accepted");
      expect(invoiced.invoice).toMatchObject({ currency: "EUR" });

      await s.asRole(outsider);
      expect(await funding.awards(org).orThrow()).toEqual([]);

      await s.service();

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like 'funding%'",
      );

      expect(new Set(events.map((row) => row.type))).toEqual(
        new Set([
          "funding_award.created",
          "funding_award.exceeded",
          "funding_delivery.registered",
          "funding_claim.created",
          "funding_claim.sent",
          "funding_claim.responded",
        ]),
      );
    } finally {
      await s.close();
    }
  });
});
