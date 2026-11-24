import { getExtracted } from "next-intl/server";

import { prescribeMedicationWithConsent } from "@/features/composites/composites-actions";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import { holds } from "@/features/sales/components/overview-support";

import { getMedicationOptions } from "../care-queries";

/**
 * Prescribes a medication for the client while their consent is active. A
 * client without the consent gets the consent error and no order.
 */
// skeleton: renders a button, behind the tab's Suspense
export async function PrescribeDialog({ clientId }: { clientId: string }) {
  const [t, allowed, options] = await Promise.all([
    getExtracted("care"),
    holds("medications.prescribe"),
    getMedicationOptions(),
  ]);

  if (!allowed || options.kind !== "ok") {
    return null;
  }

  return (
    <ActionDialog
      action={prescribeMedicationWithConsent}
      title={t("Prescribe medication")}
      description={t(
        "Prescribes only while the client's consent for the purpose is active.",
      )}
      trigger={t("Prescribe")}
      submitLabel={t("Prescribe")}
      successMessage={t("Medication prescribed")}
      hidden={{ clientId }}
      fields={[
        {
          name: "medicationId",
          label: t("Medication"),
          kind: "select",
          required: true,
          options: options.data.map((medication) => ({
            value: medication.id,
            label: medication.name,
          })),
        },
        { name: "dose", label: t("Dose"), kind: "decimal", required: true },
        {
          name: "times",
          label: t("Times of day"),
          kind: "text",
          required: true,
          defaultValue: "08:00",
          placeholder: "08:00, 20:00",
        },
        {
          name: "purposeKey",
          label: t("Consent purpose"),
          kind: "text",
          required: true,
          defaultValue: "medication",
        },
      ]}
    />
  );
}
