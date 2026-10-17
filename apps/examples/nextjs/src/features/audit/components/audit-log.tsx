import { hasEntitlement } from "better-supabase/blocks/entitlements";
import { tenantOf } from "better-supabase/next";
import { DownloadIcon, ScrollTextIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";

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
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { Link } from "@/i18n/navigation";

import { AuditLogTable } from "./audit-log-table";

/** Render inside `<Suspense>`. The log is a plan feature (`audit`). */
export async function AuditLog() {
  const [session, t] = await Promise.all([getSession(), getExtracted("audit")]);
  const organizationId = tenantOf(session);
  if (!organizationId) {
    return null;
  }
  if (!can(session, "audit.read")) {
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
    <Card>
      <CardHeader>
        <CardTitle>{t("Audit log")}</CardTitle>
        <CardDescription>
          {t("Database changes and app events, recorded by the audit module.")}
        </CardDescription>
        <CardAction>
          <FeatureGate feature="exports">
            <a
              href="/api/audit/export"
              download
              className={buttonVariants({ variant: "outline", size: "sm" })}
            >
              <DownloadIcon />
              {t("Export CSV")}
            </a>
          </FeatureGate>
        </CardAction>
      </CardHeader>
      <CardContent>
        <AuditLogTable organizationId={organizationId} />
      </CardContent>
    </Card>
  );
}

export function AuditLogSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}
