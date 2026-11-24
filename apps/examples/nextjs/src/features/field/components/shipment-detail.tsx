import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordBoundSections } from "@/components/record-detail/record-bound-sections";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordDetailTabs } from "@/components/record-detail/record-detail-tabs";
import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { settle } from "@/features/crm/crm-queries";
import {
  dateFormatter,
  requirePermission,
} from "@/features/sales/components/overview-support";

import { loadShipment } from "../field-queries";
import { FieldLoadError } from "./field-load-error";

export function ShipmentDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

/** The shipment desk: the parcel's facts and its tracking timeline. */
export async function ShipmentDetail({ id, tab }: { id: string; tab: string }) {
  await requirePermission("shipments.read");

  const [t, loaded, fmtDate] = await Promise.all([
    getExtracted("field"),
    settle(() => loadShipment(id)),
    dateFormatter(),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <FieldLoadError title={t("The shipment didn't load")} />;
  }

  const shipment = loaded.data;

  if (!shipment) {
    notFound();
  }

  const subject = { type: "shipment", id: shipment.row.id } as const;

  const facts = [
    { label: t("Carrier"), value: shipment.row.carrier },
    { label: t("Service"), value: shipment.service },
    { label: t("Tracking number"), value: shipment.row.trackingNumber },
    { label: t("From"), value: shipment.origin },
    { label: t("Parcels"), value: String(shipment.packages) },
    {
      label: t("Weight"),
      value: `${(shipment.weightGrams / 1000).toFixed(1)} kg`,
    },
    { label: t("Delivered"), value: fmtDate(shipment.deliveredAt) },
  ];

  return (
    <RecordDetailFrame
      aside={
        <>
          <PropertiesRail title={t("Details")} properties={facts} />
          <RecordBoundSections
            subject={subject}
            sections={["tags", "fields", "reminders"]}
          />
        </>
      }
      title={shipment.row.reference}
      description={shipment.row.recipient}
      status={<Badge variant="primary-light">{shipment.row.status}</Badge>}
    >
      <RecordDetailTabs
        base={`/field/shipments/${id}`}
        active={tab}
        tabs={[
          { value: "overview", label: t("Overview") },
          { value: "related", label: t("Related") },
          { value: "activity", label: t("Activity") },
        ]}
      />
      {tab === "related" ? (
        <RecordBoundSections
          subject={subject}
          sections={["files", "relations"]}
        />
      ) : tab === "activity" ? (
        <RecordBoundSections
          subject={subject}
          sections={["discussion", "history"]}
        />
      ) : (
        <>
          <Card>
            <CardHeader>
              <CardTitle>{t("Delivery address")}</CardTitle>
            </CardHeader>
            <CardContent className="flex flex-col text-sm">
              {shipment.address.map((line) => (
                <span key={line}>{line}</span>
              ))}
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle>{t("Tracking")}</CardTitle>
              <CardDescription>
                {shipment.timeline.length === 0
                  ? t("No tracking events yet.")
                  : t("Newest first.")}
              </CardDescription>
            </CardHeader>
            {shipment.timeline.length > 0 ? (
              <CardContent>
                <ol className="flex flex-col gap-3 text-sm">
                  {shipment.timeline.map((step) => (
                    <li key={step.id} className="flex flex-col gap-1">
                      <span className="flex flex-wrap items-center gap-2">
                        <Badge variant="secondary">{step.status}</Badge>
                        <span className="text-muted-foreground">
                          {fmtDate(step.occurredAt)}
                        </span>
                      </span>
                      {step.description ? (
                        <span>{step.description}</span>
                      ) : null}
                      {step.location ? (
                        <span className="text-xs text-muted-foreground">
                          {step.location}
                        </span>
                      ) : null}
                    </li>
                  ))}
                </ol>
              </CardContent>
            ) : null}
          </Card>
        </>
      )}
    </RecordDetailFrame>
  );
}
