import { getExtracted, getFormatter } from "next-intl/server";
import { forbidden, notFound } from "next/navigation";

import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { KpiBand } from "@/components/record-list/kpi-band";
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
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { loadWebhook } from "../webhooks-queries";
import {
  RedeliverButton,
  SendTestEventButton,
  WebhookEndpointActions,
} from "./webhook-endpoint-controls";
import { DeliveryStatusBadge, EndpointStatusBadge } from "./webhook-endpoints";

/** Render inside `<Suspense>`: reads the `id` param and the endpoint. */
export async function WebhookDetail({ id }: { id: string }) {
  const [detail, permissions, t, format] = await Promise.all([
    loadWebhook(id),
    getPermissions(),
    getExtracted("webhooks"),
    getFormatter(),
  ]);

  if (!can(permissions, "webhooks.read")) {
    forbidden();
  }

  if (detail === undefined || detail === null) {
    notFound();
  }

  const { endpoint, deliveries } = detail;
  const manage = can(permissions, "webhooks.manage");
  const failed = deliveries.filter((entry) => entry.status === "dead").length;

  const when = (iso: string) =>
    format.dateTime(new Date(iso), { dateStyle: "medium", timeStyle: "short" });

  const labels = {
    pending: t("Pending"),
    delivering: t("Delivering"),
    succeeded: t("Delivered"),
    retrying: t("Retrying"),
    dead: t("Failed"),
    canceled: t("Canceled"),
  };

  return (
    <RecordDetailFrame
      title={endpoint.name}
      description={endpoint.url}
      status={
        <EndpointStatusBadge
          endpoint={endpoint}
          labels={{ off: t("Off"), failing: t("Failing"), active: t("Active") }}
        />
      }
      actions={
        manage ? (
          <>
            <SendTestEventButton id={endpoint.id} />
            <WebhookEndpointActions
              id={endpoint.id}
              name={endpoint.name}
              enabled={endpoint.enabled}
            />
          </>
        ) : undefined
      }
      aside={
        <PropertiesRail
          title={t("Properties")}
          properties={[
            { label: t("Created"), value: when(endpoint.createdAt) },
            {
              label: t("Failing since"),
              value:
                endpoint.failingSince === null
                  ? undefined
                  : when(endpoint.failingSince),
            },
            { label: t("Disabled because"), value: endpoint.disabledReason },
            {
              label: t("Events"),
              value: (
                <span className="flex flex-wrap justify-end gap-1">
                  {endpoint.eventTypes.map((type) => (
                    <Badge key={type} variant="outline" className="font-mono">
                      {type}
                    </Badge>
                  ))}
                </span>
              ),
            },
          ]}
        />
      }
    >
      <KpiBand
        kpis={[
          { label: t("Deliveries"), value: String(deliveries.length) },
          {
            label: t("Delivered"),
            value: String(
              deliveries.filter((entry) => entry.status === "succeeded").length,
            ),
          },
          { label: t("Failed"), value: String(failed) },
        ]}
      />
      <Card data-testid="webhook-detail-deliveries">
        <CardHeader>
          <CardTitle>{t("Deliveries")}</CardTitle>
          <CardDescription>
            {t(
              "The last 50 events sent to this endpoint. Replay a finished one.",
            )}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {deliveries.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("No deliveries yet. Send a test event to start.")}
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("Event")}</TableHead>
                  <TableHead>{t("Status")}</TableHead>
                  <TableHead>{t("Attempts")}</TableHead>
                  <TableHead>{t("Response")}</TableHead>
                  <TableHead>{t("Created")}</TableHead>
                  {manage ? <TableHead /> : null}
                </TableRow>
              </TableHeader>
              <TableBody>
                {deliveries.map((delivery) => (
                  <TableRow key={delivery.id}>
                    <TableCell className="font-mono text-sm">
                      {delivery.eventType}
                    </TableCell>
                    <TableCell>
                      <DeliveryStatusBadge
                        status={delivery.status}
                        labels={labels}
                      />
                    </TableCell>
                    <TableCell className="tabular-nums">
                      {delivery.attempt}
                    </TableCell>
                    <TableCell
                      className="font-mono text-xs text-muted-foreground"
                      title={delivery.lastError ?? undefined}
                    >
                      {delivery.responseStatus ?? "–"}
                    </TableCell>
                    <TableCell className="text-xs text-muted-foreground">
                      {when(delivery.createdAt)}
                    </TableCell>
                    {manage ? (
                      <TableCell className="text-right">
                        {delivery.status === "dead" ||
                        delivery.status === "canceled" ||
                        delivery.status === "retrying" ? (
                          <RedeliverButton id={delivery.id} />
                        ) : null}
                      </TableCell>
                    ) : null}
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function WebhookDetailSkeleton() {
  return (
    <div className="grid items-start gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-4 lg:col-span-2">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-64 w-full" />
      </div>
      <Skeleton className="h-48 w-full" />
    </div>
  );
}
