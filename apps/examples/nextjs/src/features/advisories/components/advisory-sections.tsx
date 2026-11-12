import type { AdvisoryStatus } from "better-supabase/blocks/advisories";

import { ShieldAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import { Badge } from "@/components/reui/badge";
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
import { PermissionGate } from "@/features/user/components/permission-gate";

import {
  getAdvisories,
  getProducts,
  getVulnerabilities,
} from "../advisories-queries";
import { AdvisoriesLoadError } from "./advisories-load-error";
import { ADVISORY_STATUS_VARIANT, severityVariant } from "./advisory-labels";
import { ProductDialog } from "./product-dialog";
import { PublishAdvisoryButton } from "./publish-advisory-button";
import { TrackVulnerabilityDialog } from "./track-vulnerability-dialog";

/** Render inside `<Suspense>`: the advisories with their publish action. */
export async function AdvisoryList() {
  const [result, t] = await Promise.all([
    getAdvisories().then(
      (data) => ({ ok: true as const, data }),
      () => ({ ok: false as const }),
    ),
    getExtracted("advisories"),
  ]);

  if (!result.ok) {
    return <AdvisoriesLoadError title={t("The advisories didn't load")} />;
  }

  const statusLabels: Record<AdvisoryStatus, string> = {
    draft: t("Draft"),
    interim: t("Interim"),
    final: t("Final"),
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Advisories")}</CardTitle>
        <CardDescription>
          {t(
            "Published advisories are served as CSAF 2.0 documents under /.well-known/csaf.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {result.data.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ShieldAlertIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No advisories")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Add a product, track the vulnerabilities that affect it, then write an advisory.",
                )}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Advisory")}</TableHead>
                <TableHead>{t("Product")}</TableHead>
                <TableHead>{t("Severity")}</TableHead>
                <TableHead>{t("Status")}</TableHead>
                <TableHead className="text-right">{t("Actions")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {result.data.map((advisory) => (
                <TableRow key={advisory.id}>
                  <TableCell className="font-medium">
                    {advisory.title}
                    <span className="block text-xs text-muted-foreground">
                      {advisory.trackingId}
                    </span>
                  </TableCell>
                  <TableCell>{advisory.productName}</TableCell>
                  <TableCell>
                    <Badge variant={severityVariant(advisory.severity)}>
                      {advisory.severity ?? "-"}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    <Badge variant={ADVISORY_STATUS_VARIANT[advisory.status]}>
                      {statusLabels[advisory.status]}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-right">
                    {advisory.status === "draft" ? (
                      <PermissionGate permission="advisories.publish">
                        <PublishAdvisoryButton id={advisory.id} />
                      </PermissionGate>
                    ) : null}
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

/** Render inside `<Suspense>`: the products advisories are written for. */
export async function ProductList() {
  const [result, t] = await Promise.all([
    getProducts().then(
      (data) => ({ ok: true as const, data }),
      () => ({ ok: false as const }),
    ),
    getExtracted("advisories"),
  ]);

  if (!result.ok) {
    return <AdvisoriesLoadError title={t("The products didn't load")} />;
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Products")}</CardTitle>
        <CardDescription>
          {t("Each product has versions, an SBOM and VEX statements.")}
        </CardDescription>
        <CardAction>
          <PermissionGate permission="advisories.write">
            <ProductDialog />
          </PermissionGate>
        </CardAction>
      </CardHeader>
      <CardContent className="flex flex-wrap gap-2">
        {result.data.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("No products yet. Add the first one to start.")}
          </p>
        ) : (
          result.data.map((product) => (
            <Badge key={product.id} variant="secondary">
              {product.name}
              {product.vendor ? ` (${product.vendor})` : ""}
            </Badge>
          ))
        )}
      </CardContent>
    </Card>
  );
}

/** Render inside `<Suspense>`: tracked vulnerabilities and their scores. */
export async function VulnerabilityList() {
  const [result, t] = await Promise.all([
    getVulnerabilities().then(
      (data) => ({ ok: true as const, data }),
      () => ({ ok: false as const }),
    ),
    getExtracted("advisories"),
  ]);

  if (!result.ok) {
    return <AdvisoriesLoadError title={t("The vulnerabilities didn't load")} />;
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Vulnerabilities")}</CardTitle>
        <CardDescription>
          {t("Enriched hourly from OSV, EPSS and the CISA KEV catalog.")}
        </CardDescription>
        <CardAction>
          <PermissionGate permission="advisories.write">
            <TrackVulnerabilityDialog />
          </PermissionGate>
        </CardAction>
      </CardHeader>
      <CardContent>
        {result.data.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("No vulnerabilities tracked yet.")}
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Id")}</TableHead>
                <TableHead>{t("Severity")}</TableHead>
                <TableHead>{t("CVSS")}</TableHead>
                <TableHead>{t("EPSS")}</TableHead>
                <TableHead>{t("Known exploited")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {result.data.map((vulnerability) => (
                <TableRow key={vulnerability.id}>
                  <TableCell className="font-medium">
                    {vulnerability.vulnId}
                    {vulnerability.summary ? (
                      <span className="block text-xs text-muted-foreground">
                        {vulnerability.summary}
                      </span>
                    ) : null}
                  </TableCell>
                  <TableCell>
                    <Badge variant={severityVariant(vulnerability.severity)}>
                      {vulnerability.severity ?? "-"}
                    </Badge>
                  </TableCell>
                  <TableCell>{vulnerability.cvssScore ?? "-"}</TableCell>
                  <TableCell>
                    {vulnerability.epssScore === null
                      ? "-"
                      : `${(vulnerability.epssScore * 100).toFixed(1)}%`}
                  </TableCell>
                  <TableCell>
                    {vulnerability.kev ? (
                      <Badge variant="destructive-light">{t("Yes")}</Badge>
                    ) : (
                      t("No")
                    )}
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

export function AdvisoryListSkeleton() {
  return <Skeleton className="h-56 rounded-xl" aria-busy="true" />;
}

export function ProductListSkeleton() {
  return <Skeleton className="h-28 rounded-xl" aria-busy="true" />;
}

export function VulnerabilityListSkeleton() {
  return <Skeleton className="h-56 rounded-xl" aria-busy="true" />;
}
