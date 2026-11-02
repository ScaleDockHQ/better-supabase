import "temporal-polyfill/global";
import type {
  PrescribedOrder,
  Prescription,
} from "better-supabase/blocks/e-prescribing";

import { testPrescriptionGateway } from "better-supabase/testing";
import { describe, expect, it } from "vitest";

import { createPrescriptionGateway } from "../src/prescription-gateway.ts";
import { fakeFetch, OPTIONS } from "./fake-fetch.ts";

const AT = Temporal.Instant.from("2026-11-01T10:00:00Z");

const order: PrescribedOrder = {
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

const prescription: Prescription & { order: PrescribedOrder } = {
  id: "p1",
  organizationId: "org-1",
  orderId: "o1",
  subject: { type: "client", id: "c1" },
  prescriberId: "u1",
  prescriberName: "Dr. Jansen",
  status: "signed",
  order,
  signedAt: AT,
  createdAt: AT,
  updatedAt: AT,
};

describe("prescription gateway", () => {
  it("passes the better-supabase conformance kit", async () => {
    const gateway = createPrescriptionGateway({
      ...OPTIONS,
      fetch: fakeFetch(() => ({ json: { id: "rx-1" } })).fetch,
    });

    await expect(
      testPrescriptionGateway(gateway, { prescription }),
    ).resolves.toBeDefined();
  });

  it("posts the MedicationRequest with the prescription id as idempotency key", async () => {
    const { fetch, calls } = fakeFetch(() => ({ json: { id: "rx-1" } }));
    const gateway = createPrescriptionGateway({ ...OPTIONS, fetch });

    await gateway.deliver(
      {
        prescription,
        medicationRequest: {
          resourceType: "MedicationRequest",
          status: "active",
          intent: "order",
          subject: {},
        },
      },
      {},
    );

    expect(calls[0]?.headers.get("idempotency-key")).toBe("p1");
    expect(calls[0]?.body).toMatchObject({ resourceType: "MedicationRequest" });
  });

  it("throws when the pharmacy refuses, so the prescription stays signed", async () => {
    const gateway = createPrescriptionGateway({
      ...OPTIONS,
      fetch: fakeFetch(() => ({ status: 503 })).fetch,
    });

    await expect(
      gateway.cancel?.({ prescription, reason: "wrong dose" }, {}),
    ).rejects.toThrow(/HTTP 503/);
  });
});
