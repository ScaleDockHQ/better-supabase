import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordBoundSections } from "@/components/record-detail/record-bound-sections";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordDetailTabs } from "@/components/record-detail/record-detail-tabs";
import { StageStepper } from "@/components/record-detail/stage-stepper";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { completeVisit } from "@/features/composites/composites-actions";
import { settle } from "@/features/crm/crm-queries";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import {
  dateFormatter,
  holds,
  requirePermission,
} from "@/features/sales/components/overview-support";

import { loadWorkOrder } from "../field-queries";
import { AdvanceWorkOrderButton } from "./advance-work-order-button";
import { FieldLoadError } from "./field-load-error";
import {
  WorkOrderPriorityBadge,
  WorkOrderStatusBadge,
} from "./work-order-badges";

export function WorkOrderDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

/** The work order desk: the status path, the visit's facts, parts and activity. */
export async function WorkOrderDetail({
  id,
  tab,
}: {
  id: string;
  tab: string;
}) {
  await requirePermission("dispatch.read");

  const [t, loaded, fmtDate, canWork] = await Promise.all([
    getExtracted("field"),
    settle(() => loadWorkOrder(id)),
    dateFormatter(),
    holds("dispatch.work"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <FieldLoadError title={t("The work order didn't load")} />;
  }

  const order = loaded.data;

  if (!order) {
    notFound();
  }

  const { card } = order;
  const subject = { type: "work_order", id: card.id } as const;

  const path = [
    { id: "scheduled", name: t("Scheduled") },
    { id: "en_route", name: t("En route") },
    { id: "on_site", name: t("On site") },
    { id: "done", name: t("Done") },
  ];

  const facts = [
    { label: t("Technician"), value: order.technician },
    { label: t("Starts"), value: fmtDate(card.startsAt) },
    { label: t("Ends"), value: fmtDate(card.endsAt) },
    { label: t("Address"), value: card.address },
    {
      label: t("Priority"),
      value: <WorkOrderPriorityBadge priority={card.priority} />,
    },
    { label: t("Opened"), value: fmtDate(order.createdAt) },
  ];

  const visitOpen = card.status === "en_route" || card.status === "on_site";

  const meterOptions = [
    { value: "", label: t("No meter reading") },
    ...order.meters.map((meter) => ({
      value: meter.id,
      label: `${meter.name} (${meter.reading} ${meter.unit})`,
    })),
  ];

  return (
    <RecordDetailFrame
      aside={
        <>
          <PropertiesRail title={t("Details")} properties={facts} />
          <RecordBoundSections
            subject={subject}
            sections={[
              "tags",
              "fields",
              "approvals",
              "reminders",
              "conversations",
              "tasks",
              "workflows",
            ]}
          />
        </>
      }
      title={card.title}
      description={order.description ?? undefined}
      status={<WorkOrderStatusBadge status={card.status} />}
      actions={
        canWork ? (
          <>
            {card.status === "scheduled" ? (
              <AdvanceWorkOrderButton id={card.id} to="en_route" />
            ) : null}
            {card.status === "en_route" ? (
              <AdvanceWorkOrderButton id={card.id} to="on_site" />
            ) : null}
            {visitOpen ? (
              <ActionDialog
                action={completeVisit}
                title={t("Complete the visit")}
                description={t(
                  "Records the part and the meter reading, then marks the work order done.",
                )}
                trigger={t("Complete visit")}
                submitLabel={t("Complete visit")}
                successMessage={t("Visit completed")}
                hidden={{ workOrderId: card.id }}
                fields={[
                  { name: "note", label: t("Note"), kind: "textarea" },
                  { name: "partName", label: t("Part used"), kind: "text" },
                  {
                    name: "partQuantity",
                    label: t("Quantity"),
                    kind: "decimal",
                    placeholder: "1",
                  },
                  ...(order.meters.length > 0
                    ? [
                        {
                          name: "meterId",
                          label: t("Meter"),
                          kind: "select" as const,
                          options: meterOptions,
                        },
                        {
                          name: "reading",
                          label: t("Reading"),
                          kind: "decimal" as const,
                        },
                      ]
                    : []),
                ]}
              />
            ) : null}
          </>
        ) : undefined
      }
    >
      <RecordDetailTabs
        base={`/field/dispatch/${id}`}
        active={tab}
        tabs={[
          { value: "overview", label: t("Overview") },
          { value: "activity", label: t("Activity") },
          { value: "related", label: t("Related") },
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
              <CardTitle>{t("Visit")}</CardTitle>
              <CardDescription>
                {card.status === "unscheduled"
                  ? t("Schedule this work order on the dispatch board.")
                  : t("From the schedule to the finished job.")}
              </CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
              <StageStepper
                stages={path}
                currentId={card.status}
                label={t("Visit status")}
              />
              <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
                <dt className="text-muted-foreground">
                  {t("Left for the stop")}
                </dt>
                <dd>{fmtDate(order.enRouteAt)}</dd>
                <dt className="text-muted-foreground">{t("Arrived")}</dt>
                <dd>{fmtDate(order.arrivedAt)}</dd>
                <dt className="text-muted-foreground">{t("Completed")}</dt>
                <dd>{fmtDate(order.completedAt)}</dd>
                <dt className="text-muted-foreground">{t("Note")}</dt>
                <dd>{order.completionNote ?? "–"}</dd>
              </dl>
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle>{t("Parts used")}</CardTitle>
              <CardDescription>
                {order.parts.length === 0
                  ? t("No parts recorded yet.")
                  : t("What the visit took from stock.")}
              </CardDescription>
            </CardHeader>
            {order.parts.length > 0 ? (
              <CardContent>
                <ul className="flex flex-col gap-2 text-sm">
                  {order.parts.map((part) => (
                    <li key={part.id} className="flex justify-between gap-4">
                      <span>{part.name}</span>
                      <span className="text-muted-foreground tabular-nums">
                        {part.quantity} {part.unit ?? ""}
                      </span>
                    </li>
                  ))}
                </ul>
              </CardContent>
            ) : null}
          </Card>
        </>
      )}
    </RecordDetailFrame>
  );
}
