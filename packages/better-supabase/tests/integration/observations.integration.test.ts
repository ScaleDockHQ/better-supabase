import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createObservations } from "../../src/blocks/observations/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "permissions",
  "organizations",
  "outbox",
  "notifications",
  "subjects",
  "custom-fields",
  "share-links",
  "rate-limit",
  "forms",
  "observations",
];

// Reading a patient takes a place on its record team.
const LAYOUT = {
  subjects: {
    patient: {
      table: "public.bsb_patients",
      idType: "uuid" as const,
      title: "name",
      team: { actions: ["read"] },
    },
  },
  modules: { observations: { options: { defaults: "vitals" } } },
};

const VITALS_FORM = {
  steps: [
    {
      key: "vitals",
      title: "Vitals",
      fields: [
        {
          key: "pulse",
          label: "Pulse",
          type: "number",
          meta: { observation: "heart_rate" },
        },
        {
          key: "systolic",
          label: "Systolic",
          type: "number",
          meta: { observation: "blood_pressure", component: "systolic" },
        },
        {
          key: "diastolic",
          label: "Diastolic",
          type: "number",
          meta: { observation: "blood_pressure", component: "diastolic" },
        },
        { key: "remarks", label: "Remarks", type: "text" },
      ],
    },
  ],
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("observations", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("records, flags, alerts, corrects and maps a form to vital signs", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.rows(
        `create table public.bsb_patients (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null,
           name text not null
         )`,
      );
      await s.rows("grant select on public.bsb_patients to authenticated");
      await s.install(MODULES, LAYOUT);

      const owner = await s.user("owner");
      const nurse = await s.user("nurse");
      const lead = await s.user("lead");
      const outsider = await s.user("outsider");

      const org = await s.organization(owner, {
        member: nurse,
        member2: lead,
        member3: outsider,
      });

      await s.service();

      const [row] = await s.rows<{ id: string }>(
        "insert into public.bsb_patients (organization_id, name) values ($1, 'Pat') returning id",
        [org],
      );

      const patient = row!.id;

      await s.value(
        "better_supabase.add_subject_member('patient', $1, $2, role => 'lead')",
        [patient, lead.id],
      );
      await s.value("better_supabase.add_subject_member('patient', $1, $2)", [
        patient,
        nurse.id,
      ]);

      const observations = createObservations({
        transport: sqlTransport(s.sql),
      });

      await s.asRole(nurse);

      const definitions = await observations.definitions(org).orThrow();

      expect(definitions.map((d) => d.key)).toContain("blood_pressure");
      expect(definitions.find((d) => d.key === "heart_rate")).toMatchObject({
        system: true,
        unit: "/min",
        code: "8867-4",
      });

      const pulse = { subjectType: "patient", subjectId: patient };

      expect(
        await observations
          .record(org, { ...pulse, definitionKey: "heart_rate", value: 900 })
          .then(hint),
      ).toBe("OBSERVATION_VALUE_INVALID");
      expect(
        await observations
          .record(org, { ...pulse, definitionKey: "mood", value: "ok" })
          .then(hint),
      ).toBe("OBSERVATION_DEFINITION_NOT_FOUND");

      const critical = await observations
        .record(org, { ...pulse, definitionKey: "heart_rate", value: 135 })
        .orThrow();

      expect(critical).toMatchObject({ flag: "critical_high", value: 135 });

      await s.service();
      expect(
        await s.value<number>(
          `(select count(*)::int from better_supabase.notification_events e
            join better_supabase.notification_recipients r on r.event_id = e.id
            where e.type = 'observation.critical_recorded' and r.user_id = $1)`,
          [lead.id],
        ),
      ).toBe(1);
      expect(
        await s.value<number>(
          `(select count(*)::int from better_supabase.outbox_events
            where type = 'observation.critical_recorded' and payload ->> 'observationId' = $1)`,
          [critical.id],
        ),
      ).toBe(1);

      await s.asRole(nurse);

      const amended = await observations
        .amend(critical.id, { value: 115 }, "wrong monitor")
        .orThrow();

      expect(amended).toMatchObject({ replacesId: critical.id, flag: "high" });
      expect(
        (await observations.list("patient", patient).orThrow()).map(
          (o) => o.id,
        ),
      ).toEqual([amended.id]);

      await s.asRole(outsider);
      expect(await observations.list("patient", patient).orThrow()).toEqual([]);
      expect(
        await observations
          .saveDefinition(org, "mews", { title: "MEWS", valueType: "integer" })
          .then(hint),
      ).toBe("OBSERVATION_FORBIDDEN");

      await s.asRole(owner);

      const form = await s.value<{ id: string }>(
        "better_supabase.create_form($1, 'vitals', 'Vitals round')",
        [org],
      );

      await s.value("better_supabase.publish_form_version($1, $2)", [
        form.id,
        VITALS_FORM,
      ]);
      await s.value("better_supabase.update_form($1, null, null, 'open')", [
        form.id,
      ]);

      await s.asRole(nurse);

      const submission = await s.value<{ id: string }>(
        "better_supabase.submit_form($1, $2, 'patient', $3)",
        [
          form.id,
          { pulse: 72, systolic: 150, diastolic: 85, remarks: "calm" },
          patient,
        ],
      );

      // Every row of this transaction shares now(), so the form's rows are
      // picked by source rather than through latest().
      const fromForm = (
        await observations.list("patient", patient).orThrow()
      ).filter((o) => o.submissionId === submission.id);

      expect(
        Object.fromEntries(fromForm.map((o) => [o.definitionKey, o])),
      ).toMatchObject({
        heart_rate: { source: "form", value: 72, flag: "normal" },
        blood_pressure: {
          source: "form",
          value: { systolic: 150, diastolic: 85 },
          flag: "high",
        },
      });
      expect(fromForm).toHaveLength(2);
      expect(
        await observations.fromSubmission(submission.id).orThrow(),
      ).toEqual([]);
    } finally {
      await s.close();
    }
  });
});
