import { getExtracted } from "next-intl/server";
import { forbidden, notFound } from "next/navigation";

import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordBoundSections } from "@/components/record-detail/record-bound-sections";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordDetailTabs } from "@/components/record-detail/record-detail-tabs";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import {
  bookWithReminder,
  offboardEmployee,
} from "@/features/composites/composites-actions";
import { completeOnboardingStep } from "@/features/onboarding/onboarding-actions";
import { ActionButton } from "@/features/sales/components/action-button";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import { loadEmployeeDesk } from "../employee-desk-queries";
import { loadEmployee, settle } from "../people-queries";
import { EmployeePrivateDetails } from "./employee-private-details";
import { EmployeeStatusBadge } from "./employee-status";
import { PeopleLoadError } from "./people-load-error";

/**
 * Render inside `<Suspense>`: one employee with their manager, direct reports
 * and contracts. Private details stay behind an audited reveal.
 */
export async function EmployeeDetail({ id, tab }: { id: string; tab: string }) {
  const [t, permissions, loaded, desk] = await Promise.all([
    getExtracted("people"),
    getPermissions(),
    settle(() => loadEmployee(id)),
    settle(() => loadEmployeeDesk(id)),
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
  const subject = { type: "employee", id: employee.id } as const;
  const runs = desk.kind === "ok" ? desk.data.runs : [];
  const balances = desk.kind === "ok" ? desk.data.balances : [];
  const canWrite = can(permissions, "employees.write");
  const canTick = can(permissions, "enrollments.enroll");
  const canBook = can(permissions, "bookings.manage");

  const facts = [
    { label: t("Job title"), value: employee.jobTitle ?? "–" },
    { label: t("Email"), value: employee.email ?? "–" },
    { label: t("Reports to"), value: managerName ?? t("No one") },
    { label: t("Started"), value: employee.startDate ?? t("Not set") },
  ];

  return (
    <RecordDetailFrame
      title={employee.name}
      description={[employee.jobTitle, employee.email]
        .filter(Boolean)
        .join(" · ")}
      status={<EmployeeStatusBadge status={employee.status} />}
      aside={
        <>
          <PropertiesRail title={t("Details")} properties={facts} />
          {can(permissions, "employees.read_sensitive") ? (
            <Card size="sm">
              <CardHeader>
                <CardTitle>{t("Private details")}</CardTitle>
              </CardHeader>
              <CardContent>
                <EmployeePrivateDetails employeeId={employee.id} />
              </CardContent>
            </Card>
          ) : null}
          <RecordBoundSections
            subject={subject}
            sections={["tags", "fields", "approvals", "reminders"]}
          />
        </>
      }
      actions={
        <>
          {canBook ? (
            <ActionDialog
              action={bookWithReminder}
              title={t("Book a welcome meeting")}
              description={t(
                "Books a slot on your booking page and sets a reminder an hour before it.",
              )}
              trigger={t("Book a meeting")}
              submitLabel={t("Book")}
              successMessage={t("Meeting booked")}
              variant="outline"
              fields={[
                {
                  name: "name",
                  label: t("Guest"),
                  kind: "text",
                  required: true,
                  defaultValue: employee.name,
                },
                {
                  name: "email",
                  label: t("Guest email"),
                  kind: "text",
                  defaultValue: employee.email ?? "",
                },
                {
                  name: "date",
                  label: t("Date"),
                  kind: "date",
                  required: true,
                },
                {
                  name: "hour",
                  label: t("Start time"),
                  kind: "select",
                  required: true,
                  options: ["09", "10", "11", "13", "14", "15", "16"].map(
                    (hour) => ({ value: hour, label: `${hour}:00` }),
                  ),
                },
              ]}
            />
          ) : null}
          {canWrite && employee.status !== "offboarded" ? (
            <ActionDialog
              action={offboardEmployee}
              title={t("Offboard {name}", { name: employee.name })}
              description={t(
                "Ends the employment, cancels onboarding runs and releases open shifts.",
              )}
              trigger={t("Offboard")}
              submitLabel={t("Offboard")}
              successMessage={t("Employee offboarded")}
              hidden={{ employeeId: employee.id }}
              variant="outline"
              fields={[
                {
                  name: "endDate",
                  label: t("Last day"),
                  kind: "date",
                  required: true,
                },
                { name: "reason", label: t("Reason"), kind: "textarea" },
              ]}
            />
          ) : null}
        </>
      }
    >
      <RecordDetailTabs
        base={`/people/${id}`}
        active={tab}
        tabs={[
          { value: "overview", label: t("Overview") },
          { value: "onboarding", label: t("Onboarding") },
          { value: "activity", label: t("Activity") },
          { value: "related", label: t("Related") },
        ]}
      />
      {tab === "related" ? (
        <RecordBoundSections
          subject={subject}
          sections={["files", "relations"]}
        />
      ) : tab === "activity" ? (
        <RecordBoundSections
          subject={subject}
          sections={["discussion", "history"]}
        />
      ) : tab === "onboarding" ? (
        runs.length === 0 ? (
          <Card size="sm">
            <CardHeader>
              <CardTitle>{t("Onboarding")}</CardTitle>
              <CardDescription>
                {t("No onboarding program has been started for this person.")}
              </CardDescription>
            </CardHeader>
          </Card>
        ) : (
          runs.map((run) => (
            <Card key={run.id} size="sm">
              <CardHeader>
                <CardTitle>{run.programName}</CardTitle>
                <CardDescription>
                  {t("{done} of {total} steps done", {
                    done: String(run.steps.filter((step) => step.done).length),
                    total: String(run.steps.length),
                  })}
                </CardDescription>
              </CardHeader>
              <CardContent>
                <ul className="flex flex-col gap-2 text-sm">
                  {run.steps.map((step) => (
                    <li
                      key={step.id}
                      className="flex items-center justify-between gap-4"
                    >
                      <span
                        className={
                          step.done ? "text-muted-foreground line-through" : ""
                        }
                      >
                        {step.title}
                      </span>
                      {step.done ||
                      run.status !== "active" ||
                      !canTick ? null : (
                        <ActionButton
                          action={completeOnboardingStep}
                          input={{ enrollmentId: run.id, step: step.id }}
                          label={t("Mark done")}
                          successMessage={t("Step done")}
                        />
                      )}
                    </li>
                  ))}
                </ul>
              </CardContent>
            </Card>
          ))
        )
      ) : (
        <>
          <Card size="sm">
            <CardHeader>
              <CardTitle>{t("Leave balance")}</CardTitle>
              <CardDescription>
                {balances.length === 0
                  ? t("No leave balances you can read.")
                  : t("What is left of each leave type this period.")}
              </CardDescription>
            </CardHeader>
            {balances.length > 0 ? (
              <CardContent>
                <ul className="flex flex-col gap-2 text-sm">
                  {balances.map((balance) => (
                    <li
                      key={balance.key}
                      className="flex justify-between gap-4"
                    >
                      <span>{balance.name}</span>
                      <span className="text-muted-foreground tabular-nums">
                        {t("{available} left, {taken} taken", {
                          available: String(balance.available),
                          taken: String(balance.taken),
                        })}
                      </span>
                    </li>
                  ))}
                </ul>
              </CardContent>
            ) : null}
          </Card>
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
                <p className="text-muted-foreground">
                  {t("No direct reports.")}
                </p>
              ) : (
                reports.map((report) => (
                  <div key={report.id} className="flex justify-between gap-4">
                    <Link
                      href={`/people/${report.id}`}
                      className="hover:underline"
                    >
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
        </>
      )}
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
