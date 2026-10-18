import { BotIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";
import { unstable_rethrow } from "next/navigation";

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

import {
  loadServicePrincipals,
  type ServicePrincipalRow,
} from "../service-principals-queries";
import {
  CreateServicePrincipalDialog,
  DisableServicePrincipalButton,
} from "./service-principal-controls";

// #region recipe:service-principals-table
type PrincipalsState =
  | { readonly kind: "ok"; readonly principals: readonly ServicePrincipalRow[] }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

async function loadPrincipalsState(): Promise<PrincipalsState> {
  try {
    const principals = await loadServicePrincipals();

    return principals
      ? { kind: "ok", principals }
      : { kind: "no-organization" };
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

/**
 * Render inside `<Suspense>`: the machine identities workflows and webhooks
 * run as, with their role. Members with `service_principals.manage` add
 * and disable them. Members without `service_principals.read` see nothing.
 */
export async function ServicePrincipalsTable() {
  const [session, t, format] = await Promise.all([
    getSession(),
    getExtracted("servicePrincipals"),
    getFormatter(),
  ]);

  if (!can(session, "service_principals.read")) {
    return null;
  }

  const state = await loadPrincipalsState();

  if (state.kind === "no-organization") {
    return null;
  }

  const manage = can(session, "service_principals.manage");

  const roles = new Map([
    ["owner", t("Owner")],
    ["admin", t("Admin")],
    ["member", t("Member")],
  ]);

  return (
    <Card data-recipe="service-principals-table">
      <CardHeader>
        <CardTitle>{t("Service principals")}</CardTitle>
        <CardDescription>
          {t(
            "Machine identities that workflows and webhooks run as. They can't sign in.",
          )}
        </CardDescription>
        {manage && state.kind === "ok" ? (
          <CardAction>
            <CreateServicePrincipalDialog />
          </CardAction>
        ) : null}
      </CardHeader>
      <CardContent>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The service principals didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retry}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : state.principals.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <BotIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No service principals yet")}</EmptyTitle>
              <EmptyDescription>
                {manage
                  ? t("Add one so automations don't run as a person.")
                  : t("An admin can add one for automations.")}
              </EmptyDescription>
            </EmptyHeader>
            {manage ? (
              <EmptyContent>
                <CreateServicePrincipalDialog />
              </EmptyContent>
            ) : null}
          </Empty>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Name")}</TableHead>
                <TableHead>{t("Role")}</TableHead>
                <TableHead>{t("Status")}</TableHead>
                <TableHead>{t("Created")}</TableHead>
                {manage ? (
                  <TableHead className="text-right">{t("Actions")}</TableHead>
                ) : null}
              </TableRow>
            </TableHeader>
            <TableBody>
              {state.principals.map((principal) => (
                <TableRow key={principal.id}>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium">
                        {principal.name}
                      </span>
                      {principal.isDefault ? (
                        <Badge variant="primary-light">{t("Default")}</Badge>
                      ) : null}
                    </div>
                  </TableCell>
                  <TableCell className="text-sm">
                    {roles.get(principal.role) ?? principal.role}
                  </TableCell>
                  <TableCell>
                    {principal.disabledAt ? (
                      <Badge variant="secondary">{t("Disabled")}</Badge>
                    ) : (
                      <Badge variant="success-light">{t("Active")}</Badge>
                    )}
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {format.dateTime(new Date(principal.createdAt), {
                      dateStyle: "medium",
                    })}
                  </TableCell>
                  {manage ? (
                    <TableCell className="text-right">
                      {principal.disabledAt ? null : (
                        <DisableServicePrincipalButton
                          id={principal.id}
                          name={principal.name}
                        />
                      )}
                    </TableCell>
                  ) : null}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}

export function ServicePrincipalsTableSkeleton() {
  return <Skeleton className="h-40 rounded-xl" aria-busy="true" />;
}
// #endregion recipe:service-principals-table
