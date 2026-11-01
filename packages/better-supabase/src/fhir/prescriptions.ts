import type {
  PrescribedOrder,
  Prescription,
} from "../blocks/e-prescribing/e-prescribing.ts";
import type { FhirMedicationRequestOptions } from "./medications.ts";
import type {
  FhirIdentifier,
  FhirMedicationRequest,
  FhirMedicationRequestStatus,
} from "./types.ts";

import { toFhirMedicationRequest } from "./medications.ts";
import { compact, text, userOf } from "./shared.ts";

/** The `system` of the prescription identifier, unless the options name one. */
export const FHIR_PRESCRIPTION_SYSTEM = "urn:better-supabase:prescription";

/** The prescription fields `toFhirPrescription` reads. */
export type FhirPrescriptionSource = Pick<
  Prescription,
  "id" | "subject" | "prescriberId" | "status"
> &
  Partial<
    Pick<Prescription, "prescriberName" | "signedAt" | "cancelReason">
  > & {
    /** The order the signature froze. */
    readonly order: PrescribedOrder;
  };

function statusOf(status: Prescription["status"]): FhirMedicationRequestStatus {
  switch (status) {
    case "draft": {
      return "draft";
    }

    case "signed":
    case "sent": {
      return "active";
    }

    case "dispensed": {
      return "completed";
    }

    case "cancelled": {
      return "cancelled";
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}

/**
 * A prescription as a FHIR R4 `MedicationRequest` with intent `order`: its
 * frozen order's medication, dose and schedule, the prescriber as requester (a
 * reference from `options.user`, else the name), the signing time as
 * `authoredOn`, and the prescription id as identifier. No national format is
 * applied; a gateway adapts this resource.
 */
export function toFhirPrescription(
  prescription: FhirPrescriptionSource,
  options?: FhirMedicationRequestOptions,
): FhirMedicationRequest {
  const { order } = prescription;

  const base = toFhirMedicationRequest(
    {
      id: prescription.id,
      subject: prescription.subject,
      medicationId: order.medicationId,
      medication: {
        id: order.medicationId,
        name: order.medicationName,
        codeSystem: order.codeSystem,
        ...(order.code === undefined ? {} : { code: order.code }),
      },
      dose: order.dose,
      doseUnit: order.doseUnit,
      asNeeded: order.asNeeded,
      startsOn: order.startsOn,
      status: "active",
      ...(order.route === undefined ? {} : { route: order.route }),
      ...(order.schedule === undefined ? {} : { schedule: order.schedule }),
      ...(order.asNeededReason === undefined
        ? {}
        : { asNeededReason: order.asNeededReason }),
      ...(order.maxPerDay === undefined ? {} : { maxPerDay: order.maxPerDay }),
      ...(order.endsOn === undefined ? {} : { endsOn: order.endsOn }),
      ...(prescription.prescriberName === undefined
        ? {}
        : { prescriber: prescription.prescriberName }),
    },
    options,
  );

  const identifier: FhirIdentifier = {
    system: options?.identifierSystem ?? FHIR_PRESCRIPTION_SYSTEM,
    value: prescription.id,
  };

  return compact<FhirMedicationRequest>({
    ...base,
    identifier: [identifier],
    status: statusOf(prescription.status),
    statusReason: text(prescription.cancelReason),
    authoredOn: prescription.signedAt?.toString(),
    requester: userOf(options, prescription.prescriberId) ?? base.requester,
  });
}
