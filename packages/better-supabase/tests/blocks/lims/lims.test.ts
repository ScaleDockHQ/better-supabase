import { describe, expect, it } from "vitest";

import {
  createLims,
  limsBlock,
  limsMethodInputSchema,
  limsSampleInputSchema,
} from "../../../src/blocks/lims/index.ts";
import { temporal } from "../../../src/core/temporal-required.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";

const METHOD = {
  id: "m1",
  organizationId: "org-1",
  key: "ph",
  name: "pH",
  unit: "pH",
  lowerLimit: 6.5,
  upperLimit: 8.5,
  createdAt: AT,
  updatedAt: AT,
};

const SAMPLE = {
  id: "s1",
  organizationId: "org-1",
  number: "SMP-1",
  title: "Batch 42",
  lot: "L42",
  receivedOn: "2026-10-29",
  status: "registered",
  createdAt: AT,
  updatedAt: AT,
};

const RESULT = {
  id: "r1",
  organizationId: "org-1",
  sampleId: "s1",
  methodId: "m1",
  value: 9.1,
  outcome: "out_of_spec",
  instrumentId: "a1",
  caseId: "c1",
  testedAt: AT,
  createdAt: AT,
};

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createLims", () => {
  it("saves, archives and lists methods", async () => {
    const t = fieldsTransport({
      save_lims_method: () => METHOD,
      archive_lims_method: () => ({ ...METHOD, archivedAt: AT }),
      list_lims_methods: () => [METHOD],
    });

    const lims = createLims({ transport: t, tenant: "org-1" });

    const saved = await lims
      .saveMethod({
        input: { key: "ph", name: "pH", lowerLimit: 6.5, upperLimit: 8.5 },
      })
      .orThrow();

    const archived = await lims.archiveMethod("m1").orThrow();
    const listed = await lims.listMethods({ includeArchived: true }).orThrow();

    expect(saved).toMatchObject({
      key: "ph",
      lowerLimit: 6.5,
      upperLimit: 8.5,
    });
    expect(archived.archivedAt).toBeDefined();
    expect(listed).toHaveLength(1);
    expect(t.calls[0]).toEqual([
      "save_lims_method",
      {
        tenant: "org-1",
        input: { key: "ph", name: "pH", lowerLimit: 6.5, upperLimit: 8.5 },
      },
    ]);
    expect(t.calls[2]).toEqual([
      "list_lims_methods",
      { tenant: "org-1", include_archived: true },
    ]);
  });

  it("registers, reads, lists and moves samples", async () => {
    const t = fieldsTransport({
      register_sample: () => SAMPLE,
      get_sample: () => ({ ...SAMPLE, results: [RESULT] }),
      list_samples: () => [SAMPLE],
      complete_sample: () => ({ ...SAMPLE, status: "completed" }),
      release_sample: () => ({ ...SAMPLE, status: "released" }),
      reject_sample: () => ({
        ...SAMPLE,
        status: "rejected",
        rejectionReason: "Leaked",
      }),
    });

    const lims = createLims({ transport: t, tenant: "org-1" });
    const { PlainDate } = temporal();

    const registered = await lims
      .registerSample({
        title: "Batch 42",
        receivedOn: PlainDate.from("2026-10-29"),
      })
      .orThrow();

    const detail = await lims.getSample("s1").orThrow();
    const listed = await lims.listSamples({ status: "registered" }).orThrow();
    const completed = await lims.completeSample("s1").orThrow();
    const released = await lims.releaseSample("s1").orThrow();

    const rejected = await lims
      .rejectSample({ sampleId: "s1", reason: "Leaked" })
      .orThrow();

    expect(registered.number).toBe("SMP-1");
    expect(registered.receivedOn.toString()).toBe("2026-10-29");
    expect(detail.results[0]).toMatchObject({
      outcome: "out_of_spec",
      caseId: "c1",
    });
    expect(listed).toHaveLength(1);
    expect(completed.status).toBe("completed");
    expect(released.status).toBe("released");
    expect(rejected.rejectionReason).toBe("Leaked");
    expect(t.calls[0]).toEqual([
      "register_sample",
      {
        tenant: "org-1",
        input: { title: "Batch 42", receivedOn: "2026-10-29" },
      },
    ]);
    expect(t.calls[2]).toEqual([
      "list_samples",
      { tenant: "org-1", filters: { status: "registered" } },
    ]);
    expect(t.calls[5]).toEqual([
      "reject_sample",
      { sample_id: "s1", reason: "Leaked" },
    ]);
  });

  it("records a result and checks an instrument", async () => {
    const t = fieldsTransport({
      record_lims_result: () => RESULT,
      instrument_status: () => ({
        instrumentId: "a1",
        required: true,
        qualified: false,
      }),
    });

    const lims = createLims({ transport: t, tenant: "org-1" });
    const { PlainDate } = temporal();

    const recorded = await lims
      .recordResult({
        sampleId: "s1",
        methodId: "m1",
        input: { value: 9.1, instrumentId: "a1" },
      })
      .orThrow();

    const status = await lims
      .instrumentStatus({ assetId: "a1", on: PlainDate.from("2026-10-30") })
      .orThrow();

    expect(recorded).toMatchObject({ value: 9.1, outcome: "out_of_spec" });
    expect(status).toEqual({
      instrumentId: "a1",
      required: true,
      qualified: false,
    });
    expect(t.calls[0]).toEqual([
      "record_lims_result",
      {
        sample_id: "s1",
        method_id: "m1",
        input: { value: 9.1, instrumentId: "a1" },
      },
    ]);
    expect(t.calls[1]).toEqual([
      "instrument_status",
      { tenant: "org-1", asset_id: "a1", on_date: "2026-10-30" },
    ]);
  });

  it("runs hooks around a call", async () => {
    const seen: string[] = [];
    const t = fieldsTransport({ register_sample: () => SAMPLE });

    const lims = createLims({
      transport: t,
      tenant: "org-1",
      hooks: {
        registerSample: {
          before: () => {
            seen.push("before");
          },
          after: () => {
            seen.push("after");
          },
        },
      },
    });

    await lims.registerSample({ title: "Batch 42" }).orThrow();
    expect(seen).toEqual(["before", "after"]);
  });

  it("passes a method id and defaults the list and date arguments", async () => {
    const t = fieldsTransport({
      save_lims_method: () => ({
        ...METHOD,
        lowerLimit: "x",
        upperLimit: null,
      }),
      list_lims_methods: () => [METHOD],
      instrument_status: () => ({
        instrumentId: "a1",
        required: false,
        qualified: true,
      }),
    });

    const lims = createLims({
      transport: t,
      tenant: "org-1",
      logger: { debug() {}, info() {}, warn() {}, error() {} },
    });

    const saved = await lims
      .saveMethod({ input: { key: "ph", name: "pH" }, methodId: "m1" })
      .orThrow();

    await lims.listMethods().orThrow();
    await lims.instrumentStatus({ assetId: "a1" }).orThrow();

    expect(saved.lowerLimit).toBeUndefined();
    expect(t.calls[0]?.[1]).toMatchObject({ method_id: "m1" });
    expect(t.calls[1]).toEqual([
      "list_lims_methods",
      { tenant: "org-1", include_archived: false },
    ]);
    expect(t.calls[2]).toEqual([
      "instrument_status",
      { tenant: "org-1", asset_id: "a1" },
    ]);
  });

  it("rejects a result whose value is not a number", async () => {
    const t = fieldsTransport({
      record_lims_result: () => ({ ...RESULT, value: "9.1" }),
    });

    await expect(
      createLims({ transport: t, tenant: "org-1" })
        .recordResult({ sampleId: "s1", methodId: "m1", input: { value: 9.1 } })
        .orThrow(),
    ).rejects.toThrow(/./);
  });

  it("rejects a malformed row", async () => {
    const t = fieldsTransport({ register_sample: () => ({ id: "s1" }) });

    await expect(
      createLims({ transport: t, tenant: "org-1" })
        .registerSample({ title: "Batch 42" })
        .orThrow(),
    ).rejects.toThrow(/./);
  });

  it("has a manifest and input schemas with the SQL bounds", () => {
    expect(limsBlock.name).toBe("lims");
    expect(
      validate(limsSampleInputSchema, { title: "Batch 42" }).issues,
    ).toBeUndefined();
    expect(validate(limsSampleInputSchema, { title: "" }).issues).toBeDefined();
    expect(
      validate(limsMethodInputSchema, { key: "ph", name: "pH", lowerLimit: 6 })
        .issues,
    ).toBeUndefined();
    expect(
      validate(limsMethodInputSchema, { key: "ph", name: "" }).issues,
    ).toBeDefined();
  });
});
