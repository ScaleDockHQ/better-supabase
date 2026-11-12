import type { ReactNode } from "react";

import { formatMoney, moneyFromJson } from "better-supabase/commerce";
import { getExtracted, getFormatter, getLocale } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getClaim } from "../warranty-queries";
import { ClaimActionsBar } from "./claim-actions-bar";
import { ClaimStatusBadge } from "./claim-status";

/** One claim with its asset, amount and decision. */
export async function ClaimDetail({ id }: { id: string }): Promise<ReactNode> {
  const [claim, permissions, t, format, locale] = await Promise.all([
    getClaim(id),
    getPermissions(),
    getExtracted("warranty"),
    getFormatter(),
    getLocale(),
  ]);

  if (claim === null) {
    notFound();
  }

  return (
    <RecordDetailFrame
      title={claim.title}
      description={formatMoney(moneyFromJson(claim.amount), locale)}
      status={<ClaimStatusBadge status={claim.status} />}
      actions={
        <ClaimActionsBar
          claimId={claim.id}
          status={claim.status}
          canWrite={can(permissions, "warranty.write")}
          canDecide={can(permissions, "warranty.decide")}
        />
      }
    >
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Details")}</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-2 gap-2 text-sm">
          <span className="text-muted-foreground">{t("Asset")}</span>
          <span className="text-right">{claim.asset}</span>
          <span className="text-muted-foreground">{t("Manufacturer")}</span>
          <span className="text-right">{claim.claimant ?? "–"}</span>
          <span className="text-muted-foreground">{t("Decision")}</span>
          <span className="text-right">{claim.decision ?? "–"}</span>
          <span className="text-muted-foreground">{t("Decided")}</span>
          <span className="text-right">
            {claim.decidedAt === null
              ? "–"
              : format.dateTime(new Date(claim.decidedAt), {
                  dateStyle: "medium",
                })}
          </span>
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function ClaimDetailSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-10 w-72" />
      <RecordSectionSkeleton rows={4} />
    </div>
  );
}
