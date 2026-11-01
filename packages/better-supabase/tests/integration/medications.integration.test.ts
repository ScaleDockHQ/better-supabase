import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createMedications } from "../../src/blocks/medications/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const TABLES = `create schema medications_it;
create table medications_it.clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text not null
);
alter table medications_it.clients enable row level security;
create policy clients_read on medications_it.clients for select to authenticated using (true);
grant usage on schema medications_it to authenticated;
grant select on medications_it.clients to authenticated;`;

const MODULES = ["organizations", "outbox", "notifications", "medications"];

const LAYOUT: BlockSqlLayout = {
  subjects: { client: { table: "medications_it.clients", idType: "uuid" } },
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("medications", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("prescribes, plans, checks and records doses on a chart", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(TABLES);
      const owner = await s.user("owner");
      const nurse = await s.user("nurse");
      const aide = await s.user("aide");
      const outsider = await s.user("outsider");
      await s.install(MODULES, LAYOUT);

      const org = await s.organization(owner, { admin: nurse, member: aide });

      const [client] = await s.rows<{ id: string }>(
        "insert into medications_it.clients (organization_id, name) values ($1, 'Ada') returning id",
        [org],
      );

      const subject = { type: "client", id: client?.id ?? "" };

      const medications = createMedications({ transport: sqlTransport(s.sql) });

      await s.as(owner);

      const warfarin = await medications
        .saveMedication({
          organizationId: org,
          input: {
            name: "Warfarin",
            unit: "mg",
            codeSystem: "atc",
            code: "B01AA03",
            highRisk: true,
          },
        })
        .orThrow();

      const paracetamol = await medications
        .saveMedication({
          organizationId: org,
          input: { name: "Paracetamol", unit: "mg" },
        })
        .orThrow();

      const order = await medications
        .prescribe({
          organizationId: org,
          subject,
          medicationId: warfarin.id,
          input: {
            dose: 2,
            schedule: { times: ["08:00", "20:00"] },
            startsOn: Temporal.Now.plainDateISO("UTC").add({ days: 1 }),
          },
        })
        .orThrow();

      expect(order).toMatchObject({
        status: "active",
        doseUnit: "mg",
        subject,
        fields: {},
      });

      const planned = await medications
        .planAdministrations({
          organizationId: org,
          until: Temporal.Now.instant().add({ hours: 72 }),
        })
        .orThrow();

      expect(planned).toBeGreaterThanOrEqual(4);

      const [dose] = await s.rows<{ id: string }>(
        "select id from better_supabase.medication_administrations where order_id = $1 order by scheduled_at limit 1",
        [order.id],
      );

      const doseId = dose?.id ?? "";

      expect(
        await medications
          .recordAdministration({
            administrationId: doseId,
            input: { status: "given" },
          })
          .then(hint),
      ).toBe("MEDICATION_DOUBLE_CHECK_REQUIRED");
      expect(
        await medications
          .recordAdministration({
            administrationId: doseId,
            input: { status: "given", checkedBy: aide.id },
          })
          .then(hint),
      ).toBe("MEDICATION_DOUBLE_CHECK_REQUIRED");

      const given = await medications
        .recordAdministration({
          administrationId: doseId,
          input: { status: "given", checkedBy: nurse.id },
        })
        .orThrow();

      expect(given).toMatchObject({
        status: "given",
        dose: 2,
        performerId: owner.id,
        checkedBy: nurse.id,
      });

      const asNeeded = await medications
        .prescribe({
          organizationId: org,
          subject,
          medicationId: paracetamol.id,
          input: {
            dose: 500,
            asNeeded: true,
            asNeededReason: "pain",
            maxPerDay: 1000,
          },
        })
        .orThrow();

      await medications
        .recordAsNeeded({ orderId: asNeeded.id, input: { reason: "headache" } })
        .orThrow();
      await medications
        .recordAsNeeded({ orderId: asNeeded.id, input: { reason: "headache" } })
        .orThrow();
      expect(
        await medications
          .recordAsNeeded({
            orderId: asNeeded.id,
            input: { reason: "headache" },
          })
          .then(hint),
      ).toBe("MEDICATION_MAX_DOSE_EXCEEDED");

      await s.as(aide);
      expect(
        await medications
          .prescribe({
            organizationId: org,
            subject,
            medicationId: paracetamol.id,
            input: { dose: 1, asNeeded: true },
          })
          .then(hint),
      ).toBe("MEDICATION_FORBIDDEN");

      await s.service();

      const imported = await medications
        .importOrders({
          organizationId: org,
          orders: [
            {
              subject,
              externalId: "rx-1",
              source: "pharmacy",
              medication: {
                name: "Metformin",
                unit: "mg",
                codeSystem: "atc",
                code: "A10BA02",
              },
              dose: 500,
              schedule: { times: ["08:00"] },
            },
          ],
        })
        .orThrow();

      expect(imported.created).toHaveLength(1);
      expect(imported.created[0]).toMatchObject({
        source: "pharmacy",
        externalId: "rx-1",
      });
      expect(
        (
          await medications
            .importOrders({
              organizationId: org,
              orders: [
                {
                  subject,
                  externalId: "rx-1",
                  medicationId: paracetamol.id,
                  dose: 500,
                  asNeeded: true,
                },
              ],
            })
            .orThrow()
        ).skipped,
      ).toBe(1);

      await s.rows(
        `update better_supabase.medication_administrations set scheduled_at = now() - interval '2 hours'
         where id = (select id from better_supabase.medication_administrations
           where order_id = $1 and status = 'planned' order by scheduled_at limit 1)`,
        [order.id],
      );
      expect(await medications.markMissed().orThrow()).toBe(1);

      await s.as(nurse);

      const chart = await medications
        .chart({
          subject,
          since: Temporal.Now.instant().subtract({ hours: 24 }),
          until: Temporal.Now.instant().add({ hours: 72 }),
        })
        .orThrow();

      expect(chart.orders).toHaveLength(3);
      expect(
        chart.orders.find((row) => row.id === order.id)?.medication.name,
      ).toBe("Warfarin");
      expect(chart.administrations.map((row) => row.status)).toEqual(
        expect.arrayContaining(["given", "missed", "planned"]),
      );

      const stopped = await medications
        .stopOrder({ orderId: order.id, reason: "INR too high" })
        .orThrow();

      expect(stopped).toMatchObject({
        status: "stopped",
        stoppedReason: "INR too high",
      });
      expect(await medications.ordersOf({ subject }).orThrow()).toHaveLength(2);

      await s.asRole(outsider);
      expect(await medications.ordersOf({ subject }).orThrow()).toEqual([]);

      await s.service();

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like 'medication%'",
      );

      expect(new Set(events.map((row) => row.type))).toEqual(
        new Set([
          "medication_order.created",
          "medication_order.stopped",
          "medication_administration.recorded",
          "medication_administration.missed",
        ]),
      );
    } finally {
      await s.close();
    }
  });
});
