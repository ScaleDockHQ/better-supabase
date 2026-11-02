import { describe, expect, it } from "vitest";

import type {
  PrescribedOrder,
  Prescription,
  PrescriptionGateway,
} from "../../../src/blocks/e-prescribing/index.ts";

import {
  createEPrescribing,
  ePrescribingBlock,
} from "../../../src/blocks/e-prescribing/index.ts";
import {
  FHIR_PRESCRIPTION_SYSTEM,
  toFhirPrescription,
} from "../../../src/fhir/prescriptions.ts";
import {
  ConformanceError,
  testPrescriptionGateway,
} from "../../../src/testing/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-11-01T10:00:00Z";

const ORDER_ROW = {
  orderId: "o1",
  medicationId: "m1",
  medicationName: "Paracetamol 500 mg",
  codeSystem: "atc",
  code: "N02BE01",
  dose: 500,
  doseUnit: "mg",
  route: "oral",
  schedule: { times: ["08:00"], weekdays: [1, 2] },
  asNeeded: true,
  asNeededReason: "pain",
  maxPerDay: 4,
  startsOn: "2026-11-01",
  endsOn: "2026-11-14",
};

const DRAFT = {
  id: "p1",
  organizationId: "org-1",
  orderId: "o1",
  subjectType: "client",
  subjectId: "c1",
  prescriberId: "u1",
  status: "draft",
  createdAt: AT,
  updatedAt: AT,
};

const SIGNED = {
  ...DRAFT,
  status: "signed",
  prescriberName: "Dr. Jansen",
  order: ORDER_ROW,
  signedBy: "u1",
  signedAt: AT,
};

const SENT = {
  ...SIGNED,
  status: "sent",
  gateway: "pharmacy",
  gatewayReference: "ref-1",
  sentAt: AT,
  deliveryError: "late",
  dispensedAt: AT,
  cancelledAt: AT,
  cancelReason: "changed",
};

const pharmacy = (
  overrides: Partial<PrescriptionGateway> = {},
): PrescriptionGateway => ({
  key: "pharmacy",
  deliver: () => ({ reference: "ref-1" }),
  ...overrides,
});

const prescribing = (
  results: Parameters<typeof fieldsTransport>[0],
  gateway?: PrescriptionGateway,
) => {
  const transport = fieldsTransport(results);

  return {
    transport,
    client: createEPrescribing({
      transport,
      tenant: "org-1",
      ...(gateway ? { gateway } : {}),
    }),
  };
};

describe("createEPrescribing", () => {
  it("creates, signs, lists and reads prescriptions", async () => {
    const { client, transport } = prescribing({
      create_prescription: () => DRAFT,
      sign_prescription: () => SIGNED,
      get_prescription: () => SENT,
      list_prescriptions: () => [DRAFT],
      record_prescription_dispense: () => SENT,
    });

    const created = await client
      .create({ orderId: "o1", prescriberName: "Dr. Jansen" })
      .orThrow();

    const signed = await client.sign("p1").orThrow();
    const read = await client.get("p1").orThrow();

    const listed = await client
      .list({
        subject: { type: "client", id: "c1" },
        status: "draft",
        limit: 5,
      })
      .orThrow();

    const dispensed = await client
      .dispense({ prescriptionId: "p1", at: Temporal.Instant.from(AT) })
      .orThrow();

    expect(created.subject).toEqual({ type: "client", id: "c1" });
    expect(signed.order?.startsOn.toString()).toBe("2026-11-01");
    expect(signed.order?.schedule).toEqual({
      times: ["08:00"],
      weekdays: [1, 2],
    });
    expect(read).toMatchObject({
      gatewayReference: "ref-1",
      cancelReason: "changed",
    });
    expect(listed).toHaveLength(1);
    expect(dispensed.status).toBe("sent");
    expect(
      transport.calls.find(
        ([fn]) => fn === "record_prescription_dispense",
      )?.[1],
    ).toMatchObject({ dispensed_at: "2026-11-01T10:00:00Z" });
  });

  it("delivers a signed prescription through the gateway", async () => {
    const seen: unknown[] = [];

    const { client, transport } = prescribing(
      {
        get_prescription: () => SIGNED,
        record_prescription_delivery: () => SENT,
      },
      pharmacy({
        deliver: (delivery, request) => {
          seen.push(delivery.medicationRequest.resourceType, request);

          return { reference: "r".repeat(300) };
        },
      }),
    );

    const sent = await client.send({ prescriptionId: "p1" }).orThrow();

    expect(sent.status).toBe("sent");
    expect(seen[0]).toBe("MedicationRequest");

    const recorded = transport.calls.find(
      ([fn]) => fn === "record_prescription_delivery",
    )?.[1];

    expect(String(recorded?.["reference"])).toHaveLength(200);
  });

  it("passes the abort signal and sends without a reference", async () => {
    const controller = new AbortController();
    let signal: AbortSignal | undefined;

    const { client, transport } = prescribing(
      {
        get_prescription: () => SIGNED,
        record_prescription_delivery: () => SENT,
      },
      pharmacy({
        deliver: (_delivery, request) => {
          ({ signal } = request);

          return {};
        },
      }),
    );

    await client
      .send({ prescriptionId: "p1", signal: controller.signal })
      .orThrow();

    expect(signal).toBe(controller.signal);
    expect(
      transport.calls.find(
        ([fn]) => fn === "record_prescription_delivery",
      )?.[1],
    ).not.toHaveProperty("reference");
  });

  it("records a failed delivery and returns PRESCRIPTION_DELIVERY_FAILED", async () => {
    const { client, transport } = prescribing(
      {
        get_prescription: () => SIGNED,
        record_prescription_delivery: () => SIGNED,
      },
      pharmacy({
        deliver: () => {
          throw new Error("down");
        },
      }),
    );

    const result = await client.send({ prescriptionId: "p1" });

    expect(result.error).toMatchObject({
      hint: "PRESCRIPTION_DELIVERY_FAILED",
      status: 502,
    });
    expect(
      transport.calls.find(
        ([fn]) => fn === "record_prescription_delivery",
      )?.[1],
    ).toMatchObject({ error: "gateway pharmacy failed: down" });
  });

  it("names a non-error cause and passes on a recording failure", async () => {
    const { client } = prescribing(
      {
        get_prescription: () => SIGNED,
        record_prescription_delivery: () => {
          throw new Error("database down");
        },
      },
      pharmacy({
        deliver: () => {
          // oxlint-disable-next-line typescript/only-throw-error -- a gateway can throw anything (1 finding)
          throw "boom";
        },
      }),
    );

    const result = await client.send({ prescriptionId: "p1" });

    expect(result.ok).toBe(false);
    expect(result.error?.hint).not.toBe("PRESCRIPTION_DELIVERY_FAILED");
  });

  it("refuses to send without a gateway and a draft's request", async () => {
    const { client } = prescribing({
      get_prescription: (args) =>
        (args as { prescription_id: string }).prescription_id === "p1"
          ? SIGNED
          : DRAFT,
    });

    expect((await client.send({ prescriptionId: "p1" })).error?.hint).toBe(
      "PRESCRIPTION_GATEWAY_MISSING",
    );
    expect((await client.send({ prescriptionId: "p2" })).error?.hint).toBe(
      "PRESCRIPTION_STATUS",
    );
    expect((await client.medicationRequest("p2")).error?.hint).toBe(
      "PRESCRIPTION_STATUS",
    );
    expect((await client.medicationRequest("p1")).ok).toBe(true);
  });

  it("asks the gateway to withdraw a sent prescription before cancelling", async () => {
    const reasons: string[] = [];

    const { client } = prescribing(
      {
        get_prescription: () => SENT,
        cancel_prescription: () => ({ ...SENT, status: "cancelled" }),
      },
      pharmacy({
        cancel: ({ reason }, request) => {
          reasons.push(reason, String(request.signal === undefined));
        },
      }),
    );

    const cancelled = await client
      .cancel({ prescriptionId: "p1", reason: "wrong dose" })
      .orThrow();

    expect(cancelled.status).toBe("cancelled");
    expect(reasons).toEqual(["wrong dose", "true"]);
  });

  it("keeps a sent prescription when the gateway can't cancel it", async () => {
    const controller = new AbortController();

    const { client, transport } = prescribing(
      { get_prescription: () => SENT, cancel_prescription: () => SENT },
      pharmacy({
        cancel: () => {
          throw new Error("closed");
        },
      }),
    );

    const result = await client.cancel({
      prescriptionId: "p1",
      signal: controller.signal,
    });

    expect(result.error?.hint).toBe("PRESCRIPTION_CANCEL_FAILED");
    expect(transport.calls.some(([fn]) => fn === "cancel_prescription")).toBe(
      false,
    );
  });

  it("cancels a draft without calling the gateway", async () => {
    let called = false;

    const { client } = prescribing(
      {
        get_prescription: () => DRAFT,
        cancel_prescription: () => ({ ...DRAFT, status: "cancelled" }),
      },
      pharmacy({
        cancel: () => {
          called = true;
        },
      }),
    );

    await client.cancel({ prescriptionId: "p1" }).orThrow();
    expect(called).toBe(false);
  });

  it("rejects a gateway with an unusable key", () => {
    const transport = fieldsTransport({});

    expect(() =>
      createEPrescribing({ transport, gateway: pharmacy({ key: " " }) }),
    ).toThrow(/must be 1 to 100/);
  });

  it("needs a tenant to create and list", async () => {
    const client = createEPrescribing({ transport: fieldsTransport({}) });

    expect((await client.create({ orderId: "o1" })).ok).toBe(false);
    expect((await client.list()).ok).toBe(false);
  });

  it("registers as a block without schemas", () => {
    expect(ePrescribingBlock.name).toBe("e-prescribing");
  });
});

const frozen: PrescribedOrder = {
  orderId: "o1",
  medicationId: "m1",
  medicationName: "Paracetamol 500 mg",
  codeSystem: "atc",
  code: "N02BE01",
  dose: 500,
  doseUnit: "mg",
  route: "oral",
  asNeeded: false,
  maxPerDay: 4000,
  startsOn: Temporal.PlainDate.from("2026-11-01"),
  endsOn: Temporal.PlainDate.from("2026-11-14"),
};

const signed: Prescription & { order: PrescribedOrder } = {
  id: "p1",
  organizationId: "org-1",
  orderId: "o1",
  subject: { type: "client", id: "c1" },
  prescriberId: "u1",
  prescriberName: "Dr. Jansen",
  status: "signed",
  order: frozen,
  signedAt: Temporal.Instant.from(AT),
  createdAt: Temporal.Instant.from(AT),
  updatedAt: Temporal.Instant.from(AT),
};

describe("toFhirPrescription", () => {
  it("maps a signed prescription", () => {
    const resource = toFhirPrescription(signed);

    expect(resource).toMatchObject({
      resourceType: "MedicationRequest",
      status: "active",
      intent: "order",
      identifier: [{ system: FHIR_PRESCRIPTION_SYSTEM, value: "p1" }],
      authoredOn: AT,
    });
    expect(resource.requester).toBeDefined();
  });

  it("maps every status, the reason and a user reference", () => {
    const expected = {
      draft: "draft",
      signed: "active",
      sent: "active",
      dispensed: "completed",
      cancelled: "cancelled",
    } as const;

    for (const [status, fhir] of Object.entries(expected)) {
      expect(
        toFhirPrescription({
          ...signed,
          status: status as Prescription["status"],
        }).status,
      ).toBe(fhir);
    }

    const cancelled = toFhirPrescription(
      { ...signed, status: "cancelled", cancelReason: "wrong dose" },
      {
        identifierSystem: "urn:pharmacy",
        user: (id) => ({ reference: `Practitioner/${id}` }),
      },
    );

    expect(cancelled.statusReason?.text).toBe("wrong dose");
    expect(cancelled.identifier?.[0]?.system).toBe("urn:pharmacy");
    expect(cancelled.requester?.reference).toBe("Practitioner/u1");
  });

  it("maps a minimal order", () => {
    const {
      code: _code,
      route: _route,
      maxPerDay: _max,
      endsOn: _end,
      ...bare
    } = frozen;

    const resource = toFhirPrescription({
      id: "p2",
      subject: { type: "client", id: "c1" },
      prescriberId: "u1",
      status: "draft",
      order: bare,
    });

    expect(resource.status).toBe("draft");
    expect(resource.authoredOn).toBeUndefined();
  });
});

describe("testPrescriptionGateway", () => {
  it("passes a conforming gateway, with and without cancel", async () => {
    await expect(
      testPrescriptionGateway(pharmacy({ apiVersion: 1, cancel: () => {} }), {
        prescription: signed,
      }),
    ).resolves.toBeDefined();
    await expect(
      testPrescriptionGateway(pharmacy({ apiVersion: 1 }), {
        prescription: signed,
      }),
    ).resolves.toBeDefined();
  });

  it("fails a long reference and a bad key", async () => {
    await expect(
      testPrescriptionGateway(
        pharmacy({ deliver: () => ({ reference: "r".repeat(201) }) }),
        { prescription: signed },
      ),
    ).rejects.toBeInstanceOf(ConformanceError);
    await expect(
      testPrescriptionGateway(pharmacy({ key: "" }), { prescription: signed }),
    ).rejects.toBeInstanceOf(ConformanceError);
  });
});
