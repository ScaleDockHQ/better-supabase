import type { ReactNode } from "react";

import { formatMoney, moneyFromJson } from "better-supabase/commerce";
import { getExtracted, getFormatter, getLocale } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getLease, getLeaseCharges } from "../leases-queries";
import { LeaseActionsBar } from "./lease-actions-bar";
import { LeaseStatusBadge } from "./lease-status";
import { RecordPaymentForm } from "./record-payment-form";

export function LeaseChargesSkeleton() {
  return <RecordSectionSkeleton rows={3} />;
}

export async function LeaseCharges({ id }: { id: string }) {
  const [charges, t, format, locale] = await Promise.all([
    getLeaseCharges(id),
    getExtracted("leases"),
    getFormatter(),
    getLocale(),
  ]);

  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle>{t("Rent periods")}</CardTitle>
        <CardDescription>
          {t("The periods posted on the ledger, newest first.")}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-2 text-sm">
        {charges.length === 0 ? (
          <p className="text-muted-foreground">{t("No rent posted yet.")}</p>
        ) : (
          charges.map((charge) => (
            <div key={charge.id} className="flex justify-between gap-4">
              <span>
                {format.dateTime(new Date(charge.periodStart), {
                  dateStyle: "medium",
                })}
                {" – "}
                {format.dateTime(new Date(charge.periodEnd), {
                  dateStyle: "medium",
                })}
              </span>
              <span className="tabular-nums">
                {formatMoney(moneyFromJson(charge.amount), locale)}
              </span>
            </div>
          ))
        )}
      </CardContent>
    </Card>
  );
}

/** One lease: the head and terms from the prefetch, the rent periods after. */
export async function LeaseDetail({
  id,
  history,
}: {
  id: string;
  /** The page owns the boundary that holds this section back. */
  history: ReactNode;
}) {
  const [lease, permissions, t, locale] = await Promise.all([
    getLease(id),
    getPermissions(),
    getExtracted("leases"),
    getLocale(),
  ]);

  if (lease === null) {
    notFound();
  }

  const money = (value: typeof lease.rent) =>
    formatMoney(moneyFromJson(value), locale);

  const canManage = can(permissions, "leases.manage");

  return (
    <RecordDetailFrame
      title={lease.title}
      description={t("{start} to {end}", {
        start: lease.startsOn,
        end: lease.endsOn ?? t("open end"),
      })}
      status={<LeaseStatusBadge status={lease.status} />}
      actions={
        canManage ? (
          <LeaseActionsBar leaseId={lease.id} status={lease.status} />
        ) : null
      }
      aside={
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Terms")}</CardTitle>
          </CardHeader>
          <CardContent className="grid grid-cols-2 gap-2 text-sm">
            <span className="text-muted-foreground">{t("Rent")}</span>
            <span className="text-right tabular-nums">{money(lease.rent)}</span>
            <span className="text-muted-foreground">{t("Balance due")}</span>
            <span className="text-right tabular-nums">
              {money(lease.balanceDue)}
            </span>
            <span className="text-muted-foreground">{t("Deposit")}</span>
            <span className="text-right tabular-nums">
              {money(lease.deposit)}
            </span>
            <span className="text-muted-foreground">{t("Deposit held")}</span>
            <span className="text-right tabular-nums">
              {money(lease.depositHeld)}
            </span>
            {lease.terminationReason ? (
              <>
                <span className="text-muted-foreground">{t("Ended for")}</span>
                <span className="text-right">{lease.terminationReason}</span>
              </>
            ) : null}
          </CardContent>
        </Card>
      }
    >
      {canManage && lease.status === "active" ? (
        <Card size="sm">
          <CardContent>
            <RecordPaymentForm leaseId={lease.id} />
          </CardContent>
        </Card>
      ) : null}
      {history}
    </RecordDetailFrame>
  );
}

export function LeaseDetailSkeleton() {
  return (
    <div className="grid gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-6 lg:col-span-2">
        <Skeleton className="h-10 w-72" />
        <RecordSectionSkeleton rows={3} />
      </div>
      <RecordSectionSkeleton rows={4} />
    </div>
  );
}
