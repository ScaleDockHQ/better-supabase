import { PlugIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";

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
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
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
import { Link } from "@/i18n/navigation";

import type { MarketplaceResourceView } from "../marketplace-queries";

import { getMarketplace } from "../marketplace-queries";
import { ConnectInstallation } from "./connect-installation";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

export function resourceBadge(
  status: MarketplaceResourceView["status"],
  label: string,
) {
  return (
    <Badge variant={status === "ready" ? "success-light" : "secondary"}>
      {label}
    </Badge>
  );
}

/**
 * Render inside `<Suspense>`: the installation linked to the organization and
 * its resources, read through the member-readable
 * `marketplace_installation_for` and `marketplace_resources_for`, with a link
 * to each resource.
 */
export async function MarketplaceOverview() {
  const [read, t] = await Promise.all([
    getMarketplace(),
    getExtracted("marketplace"),
  ]);

  if (read.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The installation didn't load")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
        <AlertAction>
          <form action={retry}>
            <Button size="sm" variant="outline" type="submit">
              {t("Retry")}
            </Button>
          </form>
        </AlertAction>
      </Alert>
    );
  }

  if (read.kind === "none") {
    return (
      <div className="flex flex-col gap-6">
        <Empty className="border">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <PlugIcon />
            </EmptyMedia>
            <EmptyTitle>{t("No installation connected")}</EmptyTitle>
            <EmptyDescription>
              {t(
                "Install the app from the Vercel Marketplace, then connect its configuration below.",
              )}
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
        <ConnectInstallation />
      </div>
    );
  }

  const { installation } = read;

  return (
    <Card>
      <CardHeader>
        <CardTitle>{installation.configurationId}</CardTitle>
        <CardDescription>
          <Badge
            variant={
              installation.status === "active" ? "success-light" : "secondary"
            }
          >
            {installation.status}
          </Badge>
        </CardDescription>
      </CardHeader>
      <CardContent>
        {installation.resources.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("No resources provisioned yet.")}
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Resource")}</TableHead>
                <TableHead>{t("Plan")}</TableHead>
                <TableHead>{t("Status")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {installation.resources.map((resource) => (
                <TableRow key={resource.externalId}>
                  <TableCell className="font-medium">
                    <Link
                      href={`/settings/marketplace/${encodeURIComponent(resource.externalId)}`}
                      className="hover:underline"
                    >
                      {resource.name}
                    </Link>
                  </TableCell>
                  <TableCell>{resource.planId ?? "-"}</TableCell>
                  <TableCell>
                    {resourceBadge(resource.status, resource.status)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}

export function MarketplaceOverviewSkeleton() {
  return <Skeleton className="h-48 rounded-xl" aria-busy="true" />;
}
