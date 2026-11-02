import type { PrescriptionGateway } from "better-supabase/blocks/e-prescribing";

import type { HttpOptions } from "./http.ts";

import { record, requestJson, text } from "./http.ts";

/**
 * A `PrescriptionGateway` to a pharmacy or a national prescription service (ADR
 * 0178). It receives the signed prescription with its FHIR R4
 * `MedicationRequest`, which this template posts as is; a national format maps
 * from that resource. Throwing keeps the prescription signed so the app can
 * retry, and the key makes a retry safe.
 */
export function createPrescriptionGateway(
  options: HttpOptions,
): PrescriptionGateway {
  return {
    apiVersion: 1,
    key: "example-pharmacy",
    async deliver({ prescription, medicationRequest }, request) {
      const body = await requestJson(options, "/prescriptions", {
        method: "POST",
        body: medicationRequest,
        headers: { "idempotency-key": prescription.id },
        ...(request.signal === undefined ? {} : { signal: request.signal }),
      });

      if (!body.ok) {
        throw new Error(body.error.message);
      }

      return { reference: text(record(body.data, "receipt").id, "receipt.id") };
    },
    async cancel({ prescription, reason }, request) {
      const body = await requestJson(
        options,
        `/prescriptions/${encodeURIComponent(prescription.id)}/cancel`,
        {
          method: "POST",
          body: { reason },
          ...(request.signal === undefined ? {} : { signal: request.signal }),
        },
      );

      if (!body.ok) {
        throw new Error(body.error.message);
      }
    },
  };
}
