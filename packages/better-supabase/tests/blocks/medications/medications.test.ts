import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type { MedicationCatalog } from "../../../src/blocks/medications/index.ts";

import {
  createMedications,
  medicationInputSchema,
  medicationOrderInputSchema,
  medicationsBlock,
} from "../../../src/blocks/medications/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-30T08:00:00Z";

const MEDICATION = {
  id: "m1",
  organizationId: "org-1",
  name: "Warfarin",
  codeSystem: "atc",
  code: "B01AA03",
  form: "tablet",
  strength: "1 mg",
  unit: "mg",
  highRisk: true,
  archivedAt: null,
  createdAt: AT,
  updatedAt: AT,
};

const BARE_MEDICATION = {
  id: "m2",
  organizationId: "org-1",
  name: "Water",
  codeSystem: "custom",
  unit: "ml",
};

const ORDER = {
  id: "o1",
  organizationId: "org-1",
  subjectType: "client",
  subjectId: "c1",
  medicationId: "m1",
  dose: 2,
  doseUnit: "mg",
  route: "oral",
  schedule: {
    times: ["08:00", "20:00"],
    everyHours: null,
    startTime: "06:00",
    weekdays: [1, 3, 5],
  },
  asNeeded: false,
  asNeededReason: null,
  maxPerDay: "4",
  startsOn: "2026-10-30",
  endsOn: "2026-11-30",
  prescriber: "Dr. Visser",
  source: "pharmacy",
  externalId: "rx-1",
  requiresDoubleCheck: true,
  status: "active",
  stoppedReason: null,
  createdBy: "u9",
};

const BARE_ORDER = {
  id: "o2",
  organizationId: "org-1",
  subjectType: "client",
  subjectId: "c1",
  medicationId: "m2",
  dose: "100",
  doseUnit: "ml",
  schedule: null,
  asNeeded: true,
  startsOn: "2026-10-30",
  source: "prescriber",
  status: "stopped",
  stoppedReason: "done",
};

const DOSE = {
  id: "a1",
  organizationId: "org-1",
  orderId: "o1",
  scheduledAt: AT,
  administeredAt: AT,
  status: "given",
  dose: 2,
  performerId: "u1",
  checkedBy: "u2",
  reason: null,
  note: "Taken with water",
};

const BARE_DOSE = {
  id: "a2",
  organizationId: "org-1",
  orderId: "o2",
  status: "planned",
};

const ITEM = {
  name: "Warfarin",
  unit: "mg",
  codeSystem: "atc",
  code: "B01AA03",
  highRisk: true,
} as const;

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

const catalogOf = (
  overrides: Partial<MedicationCatalog> = {},
): MedicationCatalog => ({
  apiVersion: 1,
  search: () => Promise.resolve([ITEM]),
  get: (code) => Promise.resolve(code === ITEM.code ? ITEM : undefined),
  ...overrides,
});

describe("createMedications", () => {
  it("saves, archives, imports and lists medications", async () => {
    const t = fieldsTransport({
      save_medication: () => MEDICATION,
      archive_medication: () => ({ ...MEDICATION, archivedAt: AT }),
      import_medication: () => MEDICATION,
      list_medications: () => [MEDICATION, BARE_MEDICATION],
    });

    const medications = createMedications({ transport: t });

    const saved = await medications
      .saveMedication("org-1", {
        name: "Warfarin",
        unit: "mg",
        codeSystem: "atc",
        code: "B01AA03",
        form: "tablet",
        strength: "1 mg",
        highRisk: true,
        medicationId: "m1",
      })
      .orThrow();

    await medications
      .saveMedication("org-1", { name: "Water", unit: "ml" })
      .orThrow();

    const archived = await medications.archiveMedication("m1").orThrow();
    await medications.importMedication("org-1", ITEM).orThrow();
    const [, bare] = await medications.medications("org-1").orThrow();

    await medications
      .medications("org-1", { search: "war", includeArchived: true })
      .orThrow();

    expect(saved).toMatchObject({ highRisk: true, form: "tablet" });
    expect(archived.archivedAt?.toString()).toBe(AT);
    expect(bare).toEqual({ ...BARE_MEDICATION, highRisk: false });
    expect(t.calls).toEqual([
      [
        "save_medication",
        {
          tenant: "org-1",
          name: "Warfarin",
          unit: "mg",
          code_system: "atc",
          code: "B01AA03",
          form: "tablet",
          strength: "1 mg",
          high_risk: true,
          medication_id: "m1",
        },
      ],
      [
        "save_medication",
        {
          tenant: "org-1",
          name: "Water",
          unit: "ml",
          code_system: "custom",
          code: null,
          form: null,
          strength: null,
          high_risk: false,
          medication_id: null,
        },
      ],
      ["archive_medication", { medication_id: "m1" }],
      ["import_medication", { tenant: "org-1", item: ITEM }],
      [
        "list_medications",
        { tenant: "org-1", search: null, include_archived: false },
      ],
      [
        "list_medications",
        { tenant: "org-1", search: "war", include_archived: true },
      ],
    ]);
  });

  it("searches and imports from the catalog", async () => {
    const t = fieldsTransport({ import_medication: () => MEDICATION });

    const medications = createMedications({
      transport: t,
      catalog: catalogOf(),
    });

    const found = await medications.searchCatalog("warf").orThrow();

    const imported = await medications
      .importFromCatalog("org-1", "B01AA03", {
        signal: new AbortController().signal,
      })
      .orThrow();

    const missing = await medications.importFromCatalog("org-1", "nope");

    expect(found).toEqual([ITEM]);
    expect(imported.id).toBe("m1");
    expect(missing.ok || missing.error.hint).toBe("MEDICATION_NOT_FOUND");
    expect(t.calls).toEqual([
      ["import_medication", { tenant: "org-1", item: ITEM }],
    ]);
  });

  it("returns an error when there is no catalog or it throws", async () => {
    const t = fieldsTransport({});
    const bare = createMedications({ transport: t });
    const none = await bare.searchCatalog("warf");
    const noImport = await bare.importFromCatalog("org-1", "B01AA03");

    const failing = createMedications({
      transport: t,
      catalog: catalogOf({
        search: () => Promise.reject(new Error("catalog down")),
      }),
    });

    const failed = await failing.searchCatalog("warf");

    expect(none.ok || none.error.hint).toBe("MEDICATION_NO_CATALOG");
    expect(noImport.ok || noImport.error.hint).toBe("MEDICATION_NO_CATALOG");
    expect(failed.ok || failed.error).toMatchObject({
      message: "catalog down",
      hint: "MEDICATION_CATALOG_FAILED",
    });
    expect(() =>
      createMedications({
        transport: t,
        // SAFETY: a catalog from a newer contract, to test the version check.
        catalog: {
          ...catalogOf(),
          apiVersion: 2,
        } as unknown as MedicationCatalog,
      }),
    ).toThrow("medication catalog targets API 2");
  });

  it("prescribes, updates, pauses, resumes, stops and lists orders", async () => {
    const t = fieldsTransport({
      prescribe_medication: () => ORDER,
      update_medication_order: () => ORDER,
      pause_medication_order: (args) => ({
        ...ORDER,
        status: args["paused"] === true ? "paused" : "active",
      }),
      stop_medication_order: () => BARE_ORDER,
      medication_orders_of: () => [
        { ...ORDER, medication: MEDICATION },
        { ...BARE_ORDER, medication: BARE_MEDICATION },
      ],
    });

    const medications = createMedications({ transport: t });
    const subject = { type: "client", id: "c1" };

    const order = await medications
      .prescribe("org-1", subject, "m1", {
        dose: 2,
        schedule: { times: ["08:00", "20:00"] },
        startsOn: Temporal.PlainDate.from("2026-10-30"),
        endsOn: Temporal.PlainDate.from("2026-11-30"),
        requiresDoubleCheck: true,
      })
      .orThrow();

    await medications
      .updateOrder("o1", { dose: 3, endsOn: null, route: null })
      .orThrow();

    await medications
      .updateOrder("o1", { endsOn: Temporal.PlainDate.from("2026-12-01") })
      .orThrow();

    const paused = await medications.pauseOrder("o1").orThrow();
    const resumed = await medications.resumeOrder("o1").orThrow();
    const stopped = await medications.stopOrder("o2", "done").orThrow();

    const [withMedication, bare] = await medications
      .ordersOf(subject)
      .orThrow();

    await medications.ordersOf(subject, { includeStopped: true }).orThrow();

    expect(order).toMatchObject({
      subject,
      dose: 2,
      maxPerDay: 4,
      schedule: {
        times: ["08:00", "20:00"],
        startTime: "06:00",
        weekdays: [1, 3, 5],
      },
      source: "pharmacy",
    });
    expect(order.schedule?.everyHours).toBeUndefined();
    expect(order.startsOn.toString()).toBe("2026-10-30");
    expect(order.endsOn?.toString()).toBe("2026-11-30");
    expect(paused.status).toBe("paused");
    expect(resumed.status).toBe("active");
    expect(stopped).toMatchObject({
      status: "stopped",
      dose: 100,
      asNeeded: true,
    });
    expect(stopped.schedule).toBeUndefined();
    expect(stopped.endsOn).toBeUndefined();
    expect(withMedication?.medication.highRisk).toBe(true);
    expect(bare?.medication.code).toBeUndefined();
    expect(t.calls).toEqual([
      [
        "prescribe_medication",
        {
          tenant: "org-1",
          subject_type: "client",
          subject_id: "c1",
          medication_id: "m1",
          attrs: {
            dose: 2,
            schedule: { times: ["08:00", "20:00"] },
            requiresDoubleCheck: true,
            startsOn: "2026-10-30",
            endsOn: "2026-11-30",
          },
        },
      ],
      [
        "update_medication_order",
        { order_id: "o1", attrs: { dose: 3, route: null, endsOn: null } },
      ],
      [
        "update_medication_order",
        { order_id: "o1", attrs: { endsOn: "2026-12-01" } },
      ],
      ["pause_medication_order", { order_id: "o1", paused: true }],
      ["pause_medication_order", { order_id: "o1", paused: false }],
      ["stop_medication_order", { order_id: "o2", reason: "done" }],
      [
        "medication_orders_of",
        { subject_type: "client", subject_id: "c1", include_stopped: false },
      ],
      [
        "medication_orders_of",
        { subject_type: "client", subject_id: "c1", include_stopped: true },
      ],
    ]);
  });

  it("imports orders and marks missed doses through the service transport", async () => {
    const user = fieldsTransport({});

    const service = fieldsTransport({
      import_medication_orders: () => ({ created: [ORDER], skipped: 1 }),
      mark_missed_medication_administrations: () => 3,
    });

    const medications = createMedications({ transport: user, service });

    const imported = await medications
      .importOrders("org-1", [
        {
          subject: { type: "client", id: "c1" },
          externalId: "rx-1",
          medication: ITEM,
          dose: 2,
          schedule: { everyHours: 8, startTime: "06:00" },
          source: "pharmacy",
        },
      ])
      .orThrow();

    const missed = await medications.markMissed().orThrow();

    expect(imported.skipped).toBe(1);
    expect(imported.created[0]?.externalId).toBe("rx-1");
    expect(missed).toBe(3);
    expect(user.calls).toEqual([]);
    expect(service.calls).toEqual([
      [
        "import_medication_orders",
        {
          tenant: "org-1",
          items: [
            {
              externalId: "rx-1",
              medication: ITEM,
              dose: 2,
              schedule: { everyHours: 8, startTime: "06:00" },
              source: "pharmacy",
              subjectType: "client",
              subjectId: "c1",
            },
          ],
        },
      ],
      ["mark_missed_medication_administrations", {}],
    ]);
  });

  it("plans, records and charts doses", async () => {
    const t = fieldsTransport({
      plan_medication_administrations: () => 12,
      record_medication_administration: () => DOSE,
      record_as_needed_administration: () => ({
        ...DOSE,
        id: "a3",
        scheduledAt: null,
        reason: "pain",
      }),
      medication_chart: () => ({
        since: AT,
        until: "2026-10-31T08:00:00Z",
        orders: [{ ...ORDER, medication: MEDICATION }],
        administrations: [DOSE, BARE_DOSE],
      }),
    });

    const medications = createMedications({ transport: t });
    const until = Temporal.Instant.from("2026-11-01T00:00:00Z");

    const planned = await medications
      .planAdministrations("org-1", until)
      .orThrow();

    const given = await medications
      .recordAdministration("a1", { status: "given", checkedBy: "u2" })
      .orThrow();

    await medications
      .recordAdministration("a2", {
        status: "refused",
        dose: 1,
        reason: "asleep",
        note: "Try later",
      })
      .orThrow();

    const prn = await medications
      .recordAsNeeded("o2", { reason: "pain" })
      .orThrow();

    await medications
      .recordAsNeeded("o2", {
        reason: "pain",
        dose: 50,
        checkedBy: "u2",
        note: "Before sleep",
      })
      .orThrow();

    const chart = await medications
      .chart({ type: "client", id: "c1" })
      .orThrow();

    await medications
      .chart(
        { type: "client", id: "c1" },
        { since: Temporal.Instant.from(AT), until },
      )
      .orThrow();

    expect(planned).toBe(12);
    expect(given).toMatchObject({ status: "given", checkedBy: "u2", dose: 2 });
    expect(given.reason).toBeUndefined();
    expect(prn.scheduledAt).toBeUndefined();
    expect(chart.until.toString()).toBe("2026-10-31T08:00:00Z");
    expect(chart.orders[0]?.medication.name).toBe("Warfarin");
    expect(chart.administrations[1]).toEqual(BARE_DOSE);
    expect(t.calls).toEqual([
      [
        "plan_medication_administrations",
        { tenant: "org-1", until: "2026-11-01T00:00:00Z" },
      ],
      [
        "record_medication_administration",
        {
          administration_id: "a1",
          status: "given",
          dose: null,
          reason: null,
          checked_by: "u2",
          note: null,
        },
      ],
      [
        "record_medication_administration",
        {
          administration_id: "a2",
          status: "refused",
          dose: 1,
          reason: "asleep",
          checked_by: null,
          note: "Try later",
        },
      ],
      [
        "record_as_needed_administration",
        {
          order_id: "o2",
          dose: null,
          reason: "pain",
          checked_by: null,
          note: null,
        },
      ],
      [
        "record_as_needed_administration",
        {
          order_id: "o2",
          dose: 50,
          reason: "pain",
          checked_by: "u2",
          note: "Before sleep",
        },
      ],
      ["medication_chart", { subject_type: "client", subject_id: "c1" }],
      [
        "medication_chart",
        {
          subject_type: "client",
          subject_id: "c1",
          since: AT,
          until: "2026-11-01T00:00:00Z",
        },
      ],
    ]);
  });

  it("checks and parses the extra columns of orders", async () => {
    const Fields = v.object({ ward: v.string() });
    const stored = { ...ORDER, fields: { ward: "B" } };

    const t = fieldsTransport({
      prescribe_medication: () => stored,
      update_medication_order: () => stored,
      import_medication_orders: () => ({ created: [stored], skipped: 0 }),
      medication_orders_of: () => [{ ...stored, medication: MEDICATION }],
      medication_chart: () => ({
        since: AT,
        until: AT,
        orders: [{ ...stored, medication: MEDICATION }],
        administrations: [],
      }),
      stop_medication_order: () => ({ ...ORDER, fields: { ward: 1 } }),
    });

    const medications = createMedications({ transport: t, fields: Fields });
    const subject = { type: "client", id: "c1" };
    const day = Temporal.PlainDate.from("2026-10-30");

    const prescribed = await medications
      .prescribe("org-1", subject, "m1", {
        dose: 2,
        asNeeded: true,
        fields: { ward: "B" },
      })
      .orThrow();

    await medications
      .updateOrder("o1", { dose: 3, fields: { ward: "C" } })
      .orThrow();

    const imported = await medications
      .importOrders("org-1", [
        {
          subject,
          externalId: "rx-1",
          medicationId: "m1",
          dose: 1,
          asNeeded: true,
          startsOn: day,
          fields: { ward: "B" },
        },
      ])
      .orThrow();

    const refused = await medications.importOrders("org-1", [
      { subject, externalId: "rx-2", medicationId: "m1", dose: 1 },
      {
        subject,
        externalId: "rx-3",
        medicationId: "m1",
        dose: 1,
        // SAFETY: a value the schema refuses, to prove the client checks it.
        fields: { ward: 1 } as unknown as { ward: string },
      },
    ]);

    const listed = await medications.ordersOf(subject).orThrow();
    const chart = await medications.chart(subject).orThrow();

    expect(prescribed.fields.ward).toBe("B");
    expect(imported.created[0]?.fields.ward).toBe("B");
    expect(refused.ok ? undefined : refused.error.kind).toBe("validation");
    expect(listed[0]?.fields.ward).toBe("B");
    expect(chart.orders[0]?.fields.ward).toBe("B");
    expect((await medications.stopOrder("o1", "done")).ok).toBe(false);
    expect(t.calls.slice(0, 3)).toEqual([
      [
        "prescribe_medication",
        {
          tenant: "org-1",
          subject_type: "client",
          subject_id: "c1",
          medication_id: "m1",
          attrs: { dose: 2, asNeeded: true, fields: { ward: "B" } },
        },
      ],
      [
        "update_medication_order",
        { order_id: "o1", attrs: { dose: 3, fields: { ward: "C" } } },
      ],
      [
        "import_medication_orders",
        {
          tenant: "org-1",
          items: [
            {
              externalId: "rx-1",
              medicationId: "m1",
              dose: 1,
              asNeeded: true,
              startsOn: "2026-10-30",
              fields: { ward: "B" },
              subjectType: "client",
              subjectId: "c1",
            },
          ],
        },
      ],
    ]);
    expect(
      t.calls.filter(([fn]) => fn === "import_medication_orders"),
    ).toHaveLength(1);
  });

  it("rejects a row with an unknown status", async () => {
    const t = fieldsTransport({
      stop_medication_order: () => ({ ...ORDER, status: "deleted" }),
    });

    const result = await createMedications({ transport: t }).stopOrder(
      "o1",
      "done",
    );

    expect(result.ok).toBe(false);
  });

  it("runs hooks around the client's methods", async () => {
    const t = fieldsTransport({ archive_medication: () => MEDICATION });
    const seen: string[] = [];

    const medications = createMedications({
      transport: t,
      hooks: {
        archiveMedication: {
          before: () => {
            seen.push("before");
          },
        },
      },
    });

    await medications.archiveMedication("m1").orThrow();
    expect(seen).toEqual(["before"]);
  });
});

describe("medications schemas and manifest", () => {
  it("validates medication and order input", () => {
    expect(
      validate(medicationInputSchema, { name: "Warfarin", unit: "mg" }).issues,
    ).toBeUndefined();
    expect(
      validate(medicationInputSchema, { name: "", unit: "mg" }).issues,
    ).toBeDefined();
    expect(
      validate(medicationOrderInputSchema, {
        dose: 2,
        startsOn: Temporal.PlainDate.from("2026-10-30"),
        schedule: { times: ["08:00"] },
      }).issues,
    ).toBeUndefined();
    expect(
      validate(medicationOrderInputSchema, { dose: "two" }).issues,
    ).toBeDefined();
  });

  it("names its SQL module, options and recipe", () => {
    expect(medicationsBlock).toMatchObject({
      name: "medications",
      sql: ["medications"],
      recipes: ["medication-chart"],
      category: "people",
    });
  });
});
