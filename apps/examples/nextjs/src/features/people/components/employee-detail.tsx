import { getExtracted } from "next-intl/server";
import { forbidden, notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import { loadEmployee, settle } from "../people-queries";
import { EmployeePrivateDetails } from "./employee-private-details";
import { EmployeeStatusBadge } from "./employee-status";
import { PeopleLoadError } from "./people-load-error";

/**
 * Render inside `<Suspense>`: one employee with their manager, direct reports
 * and contracts. Private details stay behind an audited reveal.
 */
export async function EmployeeDetail({ id }: { id: string }) {
  const [t, permissions, loaded] = await Promise.all([
    getExtracted("people"),
    getPermissions(),
    settle(() => loadEmployee(id)),
  ]);

  if (!can(permissions, "employees.read")) {
    forbidden();
  }

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <PeopleLoadError title={t("This employee didn't load")} />;
  }

  if (loaded.data === "not-found") {
    notFound();
  }

  const { employee, managerName, reports, contracts } = loaded.data;

  return (
    <RecordDetailFrame
      title={employee.name}
      description={[employee.jobTitle, employee.email]
        .filter(Boolean)
        .join(" · ")}
      status={<EmployeeStatusBadge status={employee.status} />}
      aside={
        can(permissions, "employees.read_sensitive") ? (
          <Card size="sm">
            <CardHeader>
              <CardTitle>{t("Private details")}</CardTitle>
            </CardHeader>
            <CardContent>
              <EmployeePrivateDetails employeeId={employee.id} />
            </CardContent>
          </Card>
        ) : null
      }
    >
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Role")}</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-2 text-sm">
          <div className="flex justify-between gap-4">
            <span className="text-muted-foreground">{t("Reports to")}</span>
            {employee.managerId && managerName ? (
              <Link
                href={`/people/${employee.managerId}`}
                className="hover:underline"
              >
                {managerName}
              </Link>
            ) : (
              <span>{t("No one")}</span>
            )}
          </div>
          <div className="flex justify-between gap-4">
            <span className="text-muted-foreground">{t("Started")}</span>
            <span>{employee.startDate ?? t("Not set")}</span>
          </div>
        </CardContent>
      </Card>
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Direct reports")}</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-2 text-sm">
          {reports.length === 0 ? (
            <p className="text-muted-foreground">{t("No direct reports.")}</p>
          ) : (
            reports.map((report) => (
              <div key={report.id} className="flex justify-between gap-4">
                <Link href={`/people/${report.id}`} className="hover:underline">
                  {report.name}
                </Link>
                <span className="text-muted-foreground">
                  {report.jobTitle ?? ""}
                </span>
              </div>
            ))
          )}
        </CardContent>
      </Card>
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Contracts")}</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-2 text-sm">
          {contracts.length === 0 ? (
            <p className="text-muted-foreground">
              {t("No contracts you can read.")}
            </p>
          ) : (
            contracts.map((contract) => (
              <div key={contract.id} className="flex justify-between gap-4">
                <span>
                  {contract.startsOn}
                  {contract.endsOn ? ` – ${contract.endsOn}` : ""}
                </span>
                <span className="text-muted-foreground tabular-nums">
                  {contract.hoursPerWeek === null
                    ? ""
                    : t("{hours} h a week", {
                        hours: String(contract.hoursPerWeek),
                      })}
                </span>
              </div>
            ))
          )}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function EmployeeDetailSkeleton() {
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
