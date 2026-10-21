import { SendIcon, TriangleAlertIcon, WebhookIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";
import { forbidden, unstable_rethrow } from "next/navigation";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import type { WebhookEndpointRow, WebhookStatus } from "../webhook-types";
import type { WebhooksOverview } from "../webhooks-queries";

import { loadWebhooks } from "../webhooks-queries";
import {
  CreateWebhookDialog,
  RedeliverButton,
  SendTestEventButton,
  WebhookEndpointActions,
} from "./webhook-endpoint-controls";

// #region recipe:webhook-endpoints
type WebhooksState =
  | { readonly kind: "ok"; readonly overview: WebhooksOverview }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

async function loadWebhooksState(): Promise<WebhooksState> {
  try {
    const overview = await loadWebhooks();

    return overview ? { kind: "ok", overview } : { kind: "no-organization" };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

type Translate = Awaited<ReturnType<typeof getExtracted>>;

function DeliveryStatusBadge({
  status,
  t,
}: {
  status: WebhookStatus;
  t: Translate;
}) {
  switch (status) {
    case "pending": {
      return <Badge variant="info-light">{t("Pending")}</Badge>;
    }

    case "delivering": {
      return <Badge variant="info-light">{t("Delivering")}</Badge>;
    }

    case "succeeded": {
      return <Badge variant="success-light">{t("Delivered")}</Badge>;
    }

    case "retrying": {
      return <Badge variant="warning-light">{t("Retrying")}</Badge>;
    }

    case "dead": {
      return <Badge variant="destructive-light">{t("Failed")}</Badge>;
    }

    case "canceled": {
      return <Badge variant="secondary">{t("Canceled")}</Badge>;
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}

function EndpointStatusBadge({
  endpoint,
  t,
}: {
  endpoint: WebhookEndpointRow;
  t: Translate;
}) {
  if (!endpoint.enabled) {
    return <Badge variant="secondary">{t("Off")}</Badge>;
  }

  return endpoint.failingSince ? (
    <Badge variant="warning-light">{t("Failing")}</Badge>
  ) : (
    <Badge variant="success-light">{t("Active")}</Badge>
  );
}

/**
 * Render inside `<Suspense>`: the organization's webhook endpoints and their
 * latest deliveries. Members with `webhooks.manage` add, toggle, test and
 * delete endpoints, and retry finished deliveries.
 */
export async function WebhookEndpoints() {
  const [session, state, t, format] = await Promise.all([
    getSession(),
    loadWebhooksState(),
    getExtracted("webhooks"),
    getFormatter(),
  ]);

  if (!can(session, "webhooks.read")) {
    forbidden();
  }

  if (state.kind === "no-organization") {
    return null;
  }

  const manage = can(session, "webhooks.manage");

  const firstEnabled =
    state.kind === "ok"
      ? state.overview.endpoints.find((endpoint) => endpoint.enabled)
      : undefined;

  const when = (iso: string) =>
    format.dateTime(new Date(iso), { dateStyle: "medium", timeStyle: "short" });

  return (
    <div data-recipe="webhook-endpoints" className="flex flex-col gap-6">
      <Card data-testid="webhook-endpoints">
        <CardHeader>
          <CardTitle>{t("Webhook endpoints")}</CardTitle>
          <CardDescription>
            {t(
              "URLs that receive this organization's events, signed with a secret only you and the receiver know.",
            )}
          </CardDescription>
          {manage && state.kind === "ok" ? (
            <CardAction>
              <CreateWebhookDialog />
            </CardAction>
          ) : null}
        </CardHeader>
        <CardContent>
          {state.kind === "error" ? (
            <Alert variant="destructive">
              <TriangleAlertIcon />
              <AlertTitle>{t("The webhooks didn't load")}</AlertTitle>
              <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
              <AlertAction>
                <form action={retry}>
                  <Button size="sm" variant="outline" type="submit">
                    {t("Retry")}
                  </Button>
                </form>
              </AlertAction>
            </Alert>
          ) : state.overview.endpoints.length === 0 ? (
            <Empty className="border">
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <WebhookIcon />
                </EmptyMedia>
                <EmptyTitle>{t("No endpoints yet")}</EmptyTitle>
                <EmptyDescription>
                  {manage
                    ? t("Add a URL to start receiving events.")
                    : t("An admin can add a URL to receive events.")}
                </EmptyDescription>
              </EmptyHeader>
              {manage ? (
                <EmptyContent>
                  <CreateWebhookDialog />
                </EmptyContent>
              ) : null}
            </Empty>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("Endpoint")}</TableHead>
                  <TableHead>{t("Events")}</TableHead>
                  <TableHead>{t("Status")}</TableHead>
                  {manage ? (
                    <TableHead className="text-right">{t("Actions")}</TableHead>
                  ) : null}
                </TableRow>
              </TableHeader>
              <TableBody>
                {state.overview.endpoints.map((endpoint) => (
                  <TableRow key={endpoint.id}>
                    <TableCell>
                      <div className="flex flex-col gap-1">
                        <span className="text-sm font-medium">
                          {endpoint.name}
                        </span>
                        <span className="max-w-xs truncate font-mono text-xs text-muted-foreground">
                          {endpoint.url}
                        </span>
                      </div>
                    </TableCell>
                    <TableCell>
                      <div className="flex flex-wrap gap-1">
                        {endpoint.eventTypes.map((type) => (
                          <Badge
                            key={type}
                            variant="outline"
                            className="font-mono"
                          >
                            {type}
                          </Badge>
                        ))}
                      </div>
                    </TableCell>
                    <TableCell>
                      <EndpointStatusBadge endpoint={endpoint} t={t} />
                    </TableCell>
                    {manage ? (
                      <TableCell>
                        <WebhookEndpointActions
                          id={endpoint.id}
                          name={endpoint.name}
                          enabled={endpoint.enabled}
                        />
                      </TableCell>
                    ) : null}
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
      {state.kind === "ok" ? (
        <Card data-testid="webhook-deliveries">
          <CardHeader>
            <CardTitle>{t("Recent deliveries")}</CardTitle>
            <CardDescription>
              {t(
                "The last 20 events sent to your endpoints. Failed deliveries retry with backoff.",
              )}
            </CardDescription>
          </CardHeader>
          <CardContent>
            {state.overview.deliveries.length === 0 ? (
              <Empty className="border">
                <EmptyHeader>
                  <EmptyMedia variant="icon">
                    <SendIcon />
                  </EmptyMedia>
                  <EmptyTitle>{t("No deliveries yet")}</EmptyTitle>
                  <EmptyDescription>
                    {firstEnabled
                      ? t(
                          "Send a test event to {name} to check that it receives them.",
                          { name: firstEnabled.name },
                        )
                      : t("Deliveries show up here once an endpoint is on.")}
                  </EmptyDescription>
                </EmptyHeader>
                {manage && firstEnabled ? (
                  <EmptyContent>
                    <SendTestEventButton id={firstEnabled.id} />
                  </EmptyContent>
                ) : null}
              </Empty>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>{t("Event")}</TableHead>
                    <TableHead>{t("Status")}</TableHead>
                    <TableHead>{t("Attempts")}</TableHead>
                    <TableHead>{t("Response")}</TableHead>
                    <TableHead>{t("Created")}</TableHead>
                    {manage ? (
                      <TableHead className="text-right">
                        {t("Actions")}
                      </TableHead>
                    ) : null}
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {state.overview.deliveries.map((delivery) => (
                    <TableRow key={delivery.id}>
                      <TableCell>
                        <div className="flex flex-col gap-1">
                          <span className="font-mono text-sm">
                            {delivery.eventType}
                          </span>
                          <span className="text-xs text-muted-foreground">
                            {delivery.endpointName}
                          </span>
                        </div>
                      </TableCell>
                      <TableCell>
                        <DeliveryStatusBadge status={delivery.status} t={t} />
                      </TableCell>
                      <TableCell className="tabular-nums">
                        {delivery.attempt}
                      </TableCell>
                      <TableCell>
                        <span
                          className="font-mono text-xs text-muted-foreground"
                          title={delivery.lastError ?? undefined}
                        >
                          {delivery.responseStatus ?? "–"}
                        </span>
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
      ) : null}
    </div>
  );
}

export function WebhookEndpointsSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-48 rounded-xl" />
      <Skeleton className="h-64 rounded-xl" />
    </div>
  );
}
// #endregion recipe:webhook-endpoints
