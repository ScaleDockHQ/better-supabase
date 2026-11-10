import { hasEntitlement } from "better-supabase/blocks/entitlements";
import { tenantOf } from "better-supabase/next";
import { ScrollTextIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
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
import { FeatureGate } from "@/features/billing/components/feature-gate";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { Link } from "@/i18n/navigation";

import type { AuditFilters as AuditFilterValues } from "../audit-queries";

import { getAuditFacets } from "../audit-queries";
import { AuditExportButton } from "./audit-export-button";
import { AuditFilters } from "./audit-filters";
import {
  AuditRows,
  AuditRowsSkeleton,
  AuditTotal,
  AuditTotalSkeleton,
} from "./audit-rows";

/**
 * The export of the rows on screen: the same filters and window, without the
 * page cursor.
 */
function exportQuery(filters: AuditFilterValues): string {
  const params = new URLSearchParams();

  for (const key of ["actor", "type", "from", "to", "q"] as const) {
    const value = filters[key];

    if (value) {
      params.set(key, value);
    }
  }

  return params.toString();
}

async function AuditFiltersLoader({
  organizationId,
}: {
  organizationId: string;
}) {
  return <AuditFilters facets={await getAuditFacets(organizationId)} />;
}

/**
 * Render inside `<Suspense>`. The log is a plan feature (`audit`). The filters
 * come from the URL; the filter bar, the rows and the total each wait on their
 * own read.
 */
export async function AuditLog({
  filters: pending,
}: {
  filters: Promise<AuditFilterValues>;
}) {
  const [session, t, permissions, filters] = await Promise.all([
    getSession(),
    getExtracted("audit"),
    getPermissions(),
    pending,
  ]);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  if (!can(permissions, "audit.read")) {
    forbidden();
  }

  if (!hasEntitlement(session, organizationId, "audit")) {
    return (
      <Empty className="border" data-testid="audit-upsell">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <ScrollTextIcon />
          </EmptyMedia>
          <EmptyTitle>{t("The audit log is on the Pro plan")}</EmptyTitle>
          <EmptyDescription>
            {t("Upgrade to see who changed what, and to export it.")}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <Link href="/settings/billing" className={buttonVariants()}>
            {t("See plans")}
          </Link>
        </EmptyContent>
      </Empty>
    );
  }

  return (
    <Card data-recipe="audit-log-table">
      <CardHeader data-recipe="feature-gate">
        <CardTitle>{t("Audit log")}</CardTitle>
        <CardDescription>
          {t("Database changes and app events, recorded by the audit module.")}
        </CardDescription>
        <CardAction>
          <FeatureGate feature="exports">
            <AuditExportButton query={exportQuery(filters)} />
          </FeatureGate>
        </CardAction>
      </CardHeader>
      <CardContent className="grid gap-4">
        <Suspense fallback={<Skeleton className="h-8" />}>
          <AuditFiltersLoader organizationId={organizationId} />
        </Suspense>
        <Suspense fallback={<AuditRowsSkeleton />}>
          <AuditRows organizationId={organizationId} filters={filters} />
        </Suspense>
        <Suspense fallback={<AuditTotalSkeleton />}>
          <AuditTotal organizationId={organizationId} filters={filters} />
        </Suspense>
      </CardContent>
    </Card>
  );
}

export function AuditLogSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}
