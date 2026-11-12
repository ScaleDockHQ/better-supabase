import type { ReactNode } from "react";

import { getExtracted, getFormatter } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import { Badge } from "@/components/reui/badge";
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

import { getPass, getPassCheckIns } from "../passes-queries";
import { PassActionsBar } from "./pass-actions-bar";
import { PassStatusBadge } from "./pass-status";

export function PassCheckInsSkeleton() {
  return <RecordSectionSkeleton rows={3} />;
}

export async function PassCheckIns({ id }: { id: string }) {
  const [scans, t, format] = await Promise.all([
    getPassCheckIns(id),
    getExtracted("passes"),
    getFormatter(),
  ]);

  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle>{t("Check-ins")}</CardTitle>
        <CardDescription>
          {t("Every scan of this pass, newest first.")}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-2 text-sm">
        {scans.length === 0 ? (
          <p className="text-muted-foreground">{t("Not scanned yet.")}</p>
        ) : (
          scans.map((scan) => (
            <div
              key={scan.id}
              className="flex items-center justify-between gap-4"
            >
              <span className="flex items-center gap-2">
                {scan.admitted ? (
                  <Badge variant="success-light">{t("Admitted")}</Badge>
                ) : (
                  <Badge variant="destructive-light">
                    {scan.reason ?? t("Refused")}
                  </Badge>
                )}
                {scan.method}
                {scan.gate ? ` · ${scan.gate}` : ""}
              </span>
              <span className="text-muted-foreground">
                {format.dateTime(new Date(scan.createdAt), {
                  dateStyle: "medium",
                  timeStyle: "short",
                })}
              </span>
            </div>
          ))
        )}
      </CardContent>
    </Card>
  );
}

/** One pass: the head from the prefetch, the check-ins after navigation. */
export async function PassDetail({
  id,
  history,
}: {
  id: string;
  /** The page owns the boundary that holds this section back. */
  history: ReactNode;
}) {
  const [pass, permissions, t, format] = await Promise.all([
    getPass(id),
    getPermissions(),
    getExtracted("passes"),
    getFormatter(),
  ]);

  if (pass === null) {
    notFound();
  }

  return (
    <RecordDetailFrame
      title={pass.holder ?? t("Pass without a holder")}
      description={pass.kind}
      status={<PassStatusBadge status={pass.status} />}
      actions={
        <PassActionsBar
          passId={pass.id}
          status={pass.status}
          canManage={can(permissions, "passes.manage")}
          canCheckIn={can(permissions, "passes.check_in")}
        />
      }
      aside={
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Validity")}</CardTitle>
          </CardHeader>
          <CardContent className="grid grid-cols-2 gap-2 text-sm">
            <span className="text-muted-foreground">{t("Uses")}</span>
            <span className="text-right tabular-nums">
              {pass.usesAllowed === null
                ? pass.uses
                : `${pass.uses} / ${pass.usesAllowed}`}
            </span>
            <span className="text-muted-foreground">{t("Valid from")}</span>
            <span className="text-right">
              {format.dateTime(new Date(pass.validFrom), {
                dateStyle: "medium",
              })}
            </span>
            <span className="text-muted-foreground">{t("Valid until")}</span>
            <span className="text-right">
              {pass.validUntil === null
                ? t("No end")
                : format.dateTime(new Date(pass.validUntil), {
                    dateStyle: "medium",
                  })}
            </span>
          </CardContent>
        </Card>
      }
    >
      {history}
    </RecordDetailFrame>
  );
}

export function PassDetailSkeleton() {
  return (
    <div className="grid gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-6 lg:col-span-2">
        <Skeleton className="h-10 w-72" />
        <RecordSectionSkeleton rows={3} />
      </div>
      <RecordSectionSkeleton rows={3} />
    </div>
  );
}
