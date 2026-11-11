import { getExtracted, getFormatter } from "next-intl/server";
import { forbidden, notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { PeopleLoadError } from "@/features/people/components/people-load-error";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getLeaveRequest } from "../leave-queries";
import { LeaveDecision } from "./leave-decision";
import { LeaveStatusBadge } from "./leave-status";

/**
 * Render inside `<Suspense>`: one leave request with the ledger entries behind
 * it.
 */
export async function LeaveDetail({ id }: { id: string }) {
  const [t, format, permissions, loaded] = await Promise.all([
    getExtracted("people"),
    getFormatter(),
    getPermissions(),
    getLeaveRequest(id),
  ]);

  if (!can(permissions, "leave.request") && !can(permissions, "leave.read")) {
    forbidden();
  }

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <PeopleLoadError title={t("This leave request didn't load")} />;
  }

  if (!loaded.data.found) {
    notFound();
  }

  const { request, ledger, available } = loaded.data;

  const show = (value: string) =>
    format.dateTime(new Date(`${value}T00:00:00`), { dateStyle: "long" });

  const open = request.status === "pending";

  return (
    <RecordDetailFrame
      title={request.who}
      description={`${request.typeName}: ${show(request.startsOn)}${
        request.startsOn === request.endsOn ? "" : ` – ${show(request.endsOn)}`
      }`}
      status={<LeaveStatusBadge status={request.status} />}
      actions={
        <LeaveDecision
          requestId={request.id}
          approvalId={request.approvalId}
          canDecide={open && can(permissions, "leave.approve")}
          canCancel={
            (open || request.status === "approved") &&
            can(permissions, "leave.request")
          }
        />
      }
      aside={
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Balance")}</CardTitle>
          </CardHeader>
          <CardContent className="text-sm">
            {available === null
              ? t("This type isn't tracked against a balance.")
              : t("{available} {unit} available", {
                  available: String(available),
                  unit: request.unit,
                })}
          </CardContent>
        </Card>
      }
    >
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Request")}</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-2 text-sm">
          <div className="flex justify-between gap-4">
            <span className="text-muted-foreground">{t("Amount")}</span>
            <span className="tabular-nums">
              {request.amount} {request.unit}
            </span>
          </div>
          {request.note ? (
            <div className="flex justify-between gap-4">
              <span className="text-muted-foreground">{t("Note")}</span>
              <span>{request.note}</span>
            </div>
          ) : null}
        </CardContent>
      </Card>
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Ledger")}</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-2 text-sm">
          {ledger.length === 0 ? (
            <p className="text-muted-foreground">
              {t("Nothing is booked until the request is approved.")}
            </p>
          ) : (
            ledger.map((entry) => (
              <div key={entry.id} className="flex justify-between gap-4">
                <span>{entry.kind}</span>
                <span className="tabular-nums">{entry.amount}</span>
              </div>
            ))
          )}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function LeaveDetailSkeleton() {
  return (
    <div className="grid gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-6 lg:col-span-2">
        <Skeleton className="h-12" />
        <RecordSectionSkeleton rows={2} />
        <RecordSectionSkeleton rows={2} />
      </div>
      <RecordSectionSkeleton rows={1} />
    </div>
  );
}
