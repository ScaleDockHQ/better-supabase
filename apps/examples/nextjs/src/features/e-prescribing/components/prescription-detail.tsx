import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { settle } from "@/features/crm/crm-queries";
import { ActionButton } from "@/features/sales/components/action-button";
import {
  dateFormatter,
  holds,
  requirePermission,
} from "@/features/sales/components/overview-support";
import { Link } from "@/i18n/navigation";

import { cancelPrescription, signPrescription } from "../e-prescribing-actions";
import { getPrescription } from "../e-prescribing-queries";

export function PrescriptionDetailSkeleton() {
  return <Skeleton className="h-72 rounded-xl" aria-busy="true" />;
}

/**
 * The prescription's page: who prescribes what, the status path and the
 * actions.
 */
export async function PrescriptionDetail({ id }: { id: string }) {
  await requirePermission("e_prescribing.read");

  const [t, loaded, fmtDate, canSign, canCancel] = await Promise.all([
    getExtracted("prescriptions"),
    settle(() => getPrescription(id)),
    dateFormatter(),
    holds("e_prescribing.sign"),
    holds("e_prescribing.write"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The prescription didn't load")} />;
  }

  const prescription = loaded.data;

  if (!prescription) {
    notFound();
  }

  const statusLabels = {
    draft: t("Draft"),
    signed: t("Signed"),
    sent: t("Sent"),
    dispensed: t("Dispensed"),
    cancelled: t("Cancelled"),
  };

  const facts = [
    { label: t("Client"), value: prescription.clientName ?? "–" },
    { label: t("Prescriber"), value: prescription.prescriber ?? "–" },
    { label: t("Dose"), value: prescription.dose ?? "–" },
    { label: t("Route"), value: prescription.route ?? "–" },
    { label: t("Signed"), value: fmtDate(prescription.signedAt) },
    { label: t("Sent"), value: fmtDate(prescription.sentAt) },
    { label: t("Dispensed"), value: fmtDate(prescription.dispensedAt) },
  ];

  const draft = prescription.status === "draft";
  const cancellable = draft || prescription.status === "signed";

  return (
    <RecordDetailFrame
      aside={<PropertiesRail title={t("Details")} properties={facts} />}
      title={prescription.medication ?? t("Draft prescription")}
      description={prescription.clientName ?? undefined}
      status={
        <Badge
          variant={
            prescription.status === "dispensed"
              ? "success-light"
              : prescription.status === "cancelled"
                ? "secondary"
                : prescription.status === "draft"
                  ? "warning-light"
                  : "info-light"
          }
        >
          {statusLabels[prescription.status]}
        </Badge>
      }
      actions={
        <>
          {prescription.clientId === null ? null : (
            <Link
              href={`/care/${prescription.clientId}`}
              className={buttonVariants({ variant: "outline", size: "sm" })}
            >
              {t("Open dossier")}
            </Link>
          )}
          {draft && canSign ? (
            <ActionButton
              action={signPrescription}
              input={{ prescriptionId: prescription.id }}
              label={t("Sign")}
              successMessage={t("Prescription signed")}
              variant="default"
            />
          ) : null}
          {cancellable && canCancel ? (
            <ActionButton
              action={cancelPrescription}
              input={{ prescriptionId: prescription.id }}
              label={t("Cancel prescription")}
              successMessage={t("Prescription cancelled")}
            />
          ) : null}
        </>
      }
    >
      <Card>
        <CardHeader>
          <CardTitle>{t("Status")}</CardTitle>
          <CardDescription>
            {draft
              ? t("Only the prescriber signs a draft.")
              : t("The signed order is frozen.")}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4 text-sm text-muted-foreground">
          {prescription.cancelReason === null ? null : (
            <p>
              {t("Cancelled: {reason}", { reason: prescription.cancelReason })}
            </p>
          )}
          {prescription.deliveryError === null ? null : (
            <Alert variant="destructive">
              <AlertTitle>{t("Delivery failed")}</AlertTitle>
              <AlertDescription>{prescription.deliveryError}</AlertDescription>
            </Alert>
          )}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}
