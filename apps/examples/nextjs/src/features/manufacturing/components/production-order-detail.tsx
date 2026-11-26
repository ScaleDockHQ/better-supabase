import type { ProductionOrderStatus } from "better-supabase/blocks/manufacturing";

import { TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordBoundSections } from "@/components/record-detail/record-bound-sections";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordDetailTabs } from "@/components/record-detail/record-detail-tabs";
import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { ActionButton } from "@/features/sales/components/action-button";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import {
  dateFormatter,
  holds,
  requirePermission,
} from "@/features/sales/components/overview-support";

import {
  completeProductionOrder,
  releaseProductionOrder,
} from "../manufacturing-actions";
import { getProductionOrder } from "../manufacturing-queries";

export function ProductionOrderDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

function StatusBadge({
  status,
  label,
}: {
  status: ProductionOrderStatus;
  label: string;
}) {
  switch (status) {
    case "draft": {
      return <Badge variant="secondary">{label}</Badge>;
    }

    case "released": {
      return <Badge variant="info-light">{label}</Badge>;
    }

    case "in_progress": {
      return <Badge variant="warning-light">{label}</Badge>;
    }

    case "done": {
      return <Badge variant="success-light">{label}</Badge>;
    }

    case "canceled": {
      return <Badge variant="outline">{label}</Badge>;
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}

/** One production order: its operations, components and what it produced. */
export async function ProductionOrderDetail({
  id,
  tab,
}: {
  id: string;
  tab: string;
}) {
  await requirePermission("manufacturing.read");

  const [t, loaded, fmtDate, canWrite, canProduce] = await Promise.all([
    getExtracted("manufacturing"),
    getProductionOrder(id),
    dateFormatter(),
    holds("manufacturing.write"),
    holds("manufacturing.produce"),
  ]);

  if (loaded.kind === "not-found") {
    notFound();
  }

  if (loaded.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The production order didn't load")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
      </Alert>
    );
  }

  const order = loaded.data;
  const subject = { type: "production_order", id: order.id } as const;

  const statuses: Record<ProductionOrderStatus, string> = {
    draft: t("Draft"),
    released: t("Released"),
    in_progress: t("In progress"),
    done: t("Done"),
    canceled: t("Canceled"),
  };

  const facts = [
    { label: t("Product"), value: order.product },
    { label: t("Planned"), value: String(order.quantity) },
    { label: t("Produced"), value: String(order.producedQuantity) },
    { label: t("Scrap"), value: String(order.scrapQuantity) },
    { label: t("Due"), value: fmtDate(order.dueOn) },
    { label: t("Completed"), value: fmtDate(order.completedAt) },
  ];

  const backordered = order.components.filter(
    (component) => component.backordered > 0,
  );

  return (
    <RecordDetailFrame
      aside={
        <>
          <PropertiesRail title={t("Details")} properties={facts} />
          <RecordBoundSections
            subject={subject}
            sections={["tags", "fields", "approvals", "reminders"]}
            alongside={tab === "related" ? ["files", "relations"] : []}
          />
        </>
      }
      title={order.number}
      description={order.product ?? undefined}
      status={
        <StatusBadge status={order.status} label={statuses[order.status]} />
      }
      actions={
        <>
          {canWrite && order.status === "draft" ? (
            <ActionButton
              action={releaseProductionOrder}
              input={{ orderId: order.id }}
              label={t("Release")}
              successMessage={t("Order released")}
              variant="default"
            />
          ) : null}
          {canProduce &&
          (order.status === "released" || order.status === "in_progress") ? (
            <ActionDialog
              action={completeProductionOrder}
              title={t("Complete the order")}
              trigger={t("Complete")}
              submitLabel={t("Complete")}
              successMessage={t("Order completed")}
              hidden={{ orderId: order.id }}
              fields={[
                {
                  name: "produced",
                  label: t("Quantity produced"),
                  kind: "number",
                  required: true,
                  defaultValue: String(order.quantity),
                },
              ]}
            />
          ) : null}
        </>
      }
    >
      <RecordDetailTabs
        base={`/manufacturing/orders/${id}`}
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
          alongside={["tags", "fields", "approvals", "reminders"]}
        />
      ) : tab === "activity" ? (
        <RecordBoundSections
          subject={subject}
          sections={["discussion", "history"]}
        />
      ) : (
        <>
          {backordered.length > 0 ? (
            <Alert variant="warning">
              <TriangleAlertIcon />
              <AlertTitle>{t("Components are short")}</AlertTitle>
              <AlertDescription>
                {t(
                  "{count, plural, one {# component is} other {# components are}} backordered. Create the purchases from the plan board.",
                  { count: backordered.length },
                )}
              </AlertDescription>
            </Alert>
          ) : null}
          <Card>
            <CardHeader>
              <CardTitle>{t("Operations")}</CardTitle>
              <CardDescription>
                {t("The routing steps, in order.")}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>{t("Step")}</TableHead>
                    <TableHead>{t("Operation")}</TableHead>
                    <TableHead className="text-right">
                      {t("Planned minutes")}
                    </TableHead>
                    <TableHead>{t("Status")}</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {order.operations.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={4} className="text-muted-foreground">
                        {t("This bill of materials has no routing.")}
                      </TableCell>
                    </TableRow>
                  ) : (
                    order.operations.map((operation) => (
                      <TableRow key={operation.id}>
                        <TableCell>{operation.sequence}</TableCell>
                        <TableCell>{operation.title}</TableCell>
                        <TableCell className="text-right tabular-nums">
                          {operation.plannedMinutes}
                        </TableCell>
                        <TableCell>
                          <Badge variant="outline">{operation.status}</Badge>
                        </TableCell>
                      </TableRow>
                    ))
                  )}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle>{t("Components")}</CardTitle>
              <CardDescription>
                {t("What the order needs, reserves and has taken from stock.")}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>{t("Component")}</TableHead>
                    <TableHead className="text-right">{t("Needed")}</TableHead>
                    <TableHead className="text-right">
                      {t("Allocated")}
                    </TableHead>
                    <TableHead className="text-right">
                      {t("Backordered")}
                    </TableHead>
                    <TableHead className="text-right">
                      {t("Consumed")}
                    </TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {order.components.map((component) => (
                    <TableRow key={component.componentId}>
                      <TableCell>{component.product ?? "–"}</TableCell>
                      <TableCell className="text-right tabular-nums">
                        {component.quantity}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">
                        {component.allocated}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">
                        {component.backordered}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">
                        {component.consumed}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        </>
      )}
    </RecordDetailFrame>
  );
}
