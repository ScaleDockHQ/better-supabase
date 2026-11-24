import { getExtracted } from "next-intl/server";

import { KpiBand, KpiBandSkeleton } from "@/components/record-list/kpi-band";
import { holds } from "@/features/sales/components/overview-support";

import { getDossierSummary } from "../care-queries";
import { CareLoadError } from "./care-load-error";

export { KpiBandSkeleton as ClientDossierSummarySkeleton };

/**
 * The counts the dossier holds, from `care.dossier`. It asks for the parts the
 * call reads, so a member without one of them sees no band instead of an
 * error.
 */
// skeleton: the dossier's Suspense fallback is ClientDossierSummarySkeleton
export async function ClientDossierSummary({ clientId }: { clientId: string }) {
  const [t, ...allowed] = await Promise.all([
    getExtracted("care"),
    holds("care_plans.read"),
    holds("observations.read"),
    holds("medications.read"),
    holds("consents.read"),
    holds("funding.read"),
  ]);

  if (allowed.includes(false)) {
    return null;
  }

  const summary = await getDossierSummary(clientId);

  if (summary.kind === "no-organization") {
    return null;
  }

  if (summary.kind === "error") {
    return <CareLoadError title={t("The dossier summary didn't load")} />;
  }

  const { plans, observations, orders, consents, funding } = summary.data;

  return (
    <KpiBand
      kpis={[
        { label: t("Care plans"), value: String(plans) },
        { label: t("Observations"), value: String(observations) },
        { label: t("Active medication"), value: String(orders) },
        { label: t("Consents"), value: String(consents) },
        { label: t("Funding awards"), value: String(funding) },
      ]}
    />
  );
}
