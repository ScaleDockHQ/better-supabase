import { FileSignatureIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { unstable_rethrow } from "next/navigation";

import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";

import { KpiBand, KpiBandSkeleton } from "@/components/record-list/kpi-band";
import { getClients } from "@/features/care/care-queries";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { BlockOverview } from "@/features/sales/components/block-overview";
import {
  dateFormatter,
  overviewContext,
  requirePermission,
} from "@/features/sales/components/overview-support";
import { facetTotals, totalOf } from "@/lib/facet-totals";

export { KpiBandSkeleton as PrescriptionKpisSkeleton };

const prescriptionMap = {
  sorts: {
    created: { by: "createdAt", direction: "desc" },
    signed: { by: "signedAt", direction: "desc" },
  },
  filters: { f: "status" },
  facets: { f: "status" },
} as const;

/** The figures above the list: prescriptions by status. */
// skeleton: the page's Suspense fallback is PrescriptionKpisSkeleton
export async function PrescriptionKpis() {
  await requirePermission("e_prescribing.read");

  const [t, context] = await Promise.all([
    getExtracted("prescriptions"),
    overviewContext(),
  ]);

  if (context === null) {
    return null;
  }

  let totals: Readonly<Record<string, number>>;

  try {
    totals = facetTotals(
      await context.db.ePrescribing.prescriptionFacets({}).orThrow(),
      "status",
    );
  } catch (error) {
    unstable_rethrow(error);

    return <CrmLoadError title={t("The prescription figures didn't load")} />;
  }

  return (
    <KpiBand
      kpis={[
        { label: t("Prescriptions"), value: String(totalOf(totals)) },
        {
          label: t("To sign"),
          value: String(totals["draft"] ?? 0),
          href: "/prescriptions?f=draft",
        },
        {
          label: t("Signed"),
          value: String((totals["signed"] ?? 0) + (totals["sent"] ?? 0)),
          href: "/prescriptions?f=signed",
        },
        {
          label: t("Dispensed"),
          value: String(totals["dispensed"] ?? 0),
          href: "/prescriptions?f=dispensed",
        },
      ]}
    />
  );
}

/** The prescriptions of the organization, each opening its page. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function PrescriptionOverview({
  query,
}: {
  query: RecordListUrlQuery;
}) {
  await requirePermission("e_prescribing.read");

  const [t, fmtDate, clients] = await Promise.all([
    getExtracted("prescriptions"),
    dateFormatter(),
    getClients(),
  ]);

  const names = new Map(
    clients.kind === "ok"
      ? clients.data.map((client) => [client.id, client.name])
      : [],
  );

  const statusLabels = {
    draft: t("Draft"),
    signed: t("Signed"),
    sent: t("Sent"),
    dispensed: t("Dispensed"),
    cancelled: t("Cancelled"),
  };

  return (
    <BlockOverview
      pager={({ db }) => ({
        page: (options) => db.ePrescribing.prescriptionPage(options),
        facets: (options) => db.ePrescribing.prescriptionFacets(options),
      })}
      map={prescriptionMap}
      query={query}
      toRow={(prescription) => ({
        id: prescription.id,
        prescription:
          prescription.order?.medicationName ?? t("Draft prescription"),
        client: names.get(prescription.subject.id) ?? "",
        prescriber: prescription.prescriberName ?? "",
        status: prescription.status,
        signedAt: fmtDate(prescription.signedAt?.toString() ?? null),
      })}
      columns={[
        {
          key: "prescription",
          header: t("Prescription"),
          kind: "link",
          href: "/prescriptions/{id}",
          size: 260,
        },
        { key: "client", header: t("Client"), kind: "muted", size: 200 },
        {
          key: "prescriber",
          header: t("Prescriber"),
          kind: "muted",
          size: 180,
        },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 130,
          labels: statusLabels,
          tones: {
            draft: "warning-light",
            signed: "info-light",
            sent: "info-light",
            dispensed: "success-light",
          },
        },
        { key: "signedAt", header: t("Signed"), kind: "muted", size: 130 },
      ]}
      facet={{ key: "status", label: t("Status"), values: statusLabels }}
      sorts={[
        { value: "created", label: t("Newest") },
        { value: "signed", label: t("Recently signed") },
      ]}
      errorTitle={t("The prescriptions didn't load")}
      emptyIcon={<FileSignatureIcon />}
      emptyTitle={t("No prescriptions found")}
      emptyDescription={t(
        "A prescriber signs a draft, then a gateway sends it to the pharmacy. Prescribe from a client's medication tab.",
      )}
    />
  );
}
