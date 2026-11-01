import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createClinicalDecisionSupport } from "../../src/blocks/clinical-decision-support/index.ts";
import { createMedications } from "../../src/blocks/medications/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const TABLES = `create schema cds_it;
create table cds_it.clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text not null
);
alter table cds_it.clients enable row level security;
create policy clients_read on cds_it.clients for select to authenticated using (true);
grant usage on schema cds_it to authenticated;
grant select on cds_it.clients to authenticated;`;

const MODULES = [
  "organizations",
  "outbox",
  "audit",
  "medications",
  "clinical-decision-support",
];

const LAYOUT: BlockSqlLayout = {
  subjects: { client: { table: "cds_it.clients", idType: "uuid" } },
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("clinical-decision-support", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("raises dose, duplicate and interaction alerts and records decisions", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(TABLES);
      const owner = await s.user("owner");
      const aide = await s.user("aide");
      await s.install(MODULES, LAYOUT);
      const org = await s.organization(owner, { member: aide });

      const [client] = await s.rows<{ id: string }>(
        "insert into cds_it.clients (organization_id, name) values ($1, 'Ada') returning id",
        [org],
      );

      const subject = { type: "client", id: client?.id ?? "" };
      const transport = sqlTransport(s.sql);
      const medications = createMedications({ transport });
      const cds = createClinicalDecisionSupport({ transport, tenant: org });

      await s.as(owner);

      const paracetamol = await medications
        .saveMedication({
          organizationId: org,
          input: { name: "Paracetamol", unit: "mg" },
        })
        .orThrow();

      const warfarin = await medications
        .saveMedication({
          organizationId: org,
          input: { name: "Warfarin", unit: "mg" },
        })
        .orThrow();

      const ibuprofen = await medications
        .saveMedication({
          organizationId: org,
          input: { name: "Ibuprofen", unit: "mg" },
        })
        .orThrow();

      await cds
        .saveRule({
          kind: "dose_range",
          medicationIds: [paracetamol.id],
          maxDose: 1000,
          severity: "critical",
        })
        .orThrow();

      await cds
        .saveRule({
          kind: "interaction",
          medicationIds: [warfarin.id, ibuprofen.id],
        })
        .orThrow();

      await medications
        .prescribe({
          organizationId: org,
          subject,
          medicationId: paracetamol.id,
          input: { dose: 2000, schedule: { times: ["08:00"] } },
        })
        .orThrow();

      await medications
        .prescribe({
          organizationId: org,
          subject,
          medicationId: paracetamol.id,
          input: { dose: 500, schedule: { times: ["12:00"] } },
        })
        .orThrow();

      await medications
        .prescribe({
          organizationId: org,
          subject,
          medicationId: warfarin.id,
          input: { dose: 2, schedule: { times: ["20:00"] } },
        })
        .orThrow();

      await medications
        .prescribe({
          organizationId: org,
          subject,
          medicationId: ibuprofen.id,
          input: { dose: 400, schedule: { times: ["09:00"] } },
        })
        .orThrow();

      const alerts = await cds.evaluate({ subject }).orThrow();
      const kinds = alerts.map((alert) => alert.kind).toSorted();

      expect(kinds).toEqual(["dose_range", "duplicate_therapy", "interaction"]);
      expect(alerts[0]?.severity).toBe("critical");

      const again = await cds.evaluate({ subject }).orThrow();

      expect(again).toHaveLength(3);

      const critical = alerts.find((alert) => alert.severity === "critical");

      expect(
        await cds
          .decide({ alertId: critical?.id ?? "", decision: "acknowledged" })
          .then(hint),
      ).toBe("CARE_ALERT_INVALID");

      const decided = await cds
        .decide({
          alertId: critical?.id ?? "",
          decision: "overridden",
          reason: "Palliative",
        })
        .orThrow();

      expect(decided).toMatchObject({
        status: "overridden",
        decisionReason: "Palliative",
      });

      const kept = await cds.evaluate({ subject }).orThrow();

      expect(kept.find((alert) => alert.id === critical?.id)?.status).toBe(
        "overridden",
      );

      await s.as(aide);

      expect(await cds.evaluate({ subject }).then(hint)).toBe(
        "CARE_ALERT_FORBIDDEN",
      );
      expect(
        await cds
          .saveRule({ kind: "interaction", medicationIds: [warfarin.id] })
          .then(hint),
      ).toBe("CARE_ALERT_FORBIDDEN");
    } finally {
      await s.close();
    }
  });
});
