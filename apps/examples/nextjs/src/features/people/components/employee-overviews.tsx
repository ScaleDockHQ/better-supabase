import {
  CalendarOffIcon,
  UserCheckIcon,
  UserPlusIcon,
  UsersIcon,
} from "lucide-react";
import { getExtracted } from "next-intl/server";

import { KpiBand } from "@/components/record-list/kpi-band";
import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { onboardEmployee } from "@/features/composites/composites-actions";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import {
  holds,
  requirePermission,
} from "@/features/sales/components/overview-support";
import { Link } from "@/i18n/navigation";

import { getOnboardingPrograms } from "../employee-desk/employee-desk-queries";
import { getRoster, settle } from "../people-queries";
import { PeopleLoadError } from "./people-load-error";

/** The figures above the people overview. */
// skeleton: the page's Suspense fallback is KpiBandSkeleton
export async function EmployeeKpis() {
  await requirePermission("employees.read");

  const [t, roster] = await Promise.all([
    getExtracted("people"),
    settle(getRoster),
  ]);

  if (roster.kind === "no-organization") {
    return null;
  }

  if (roster.kind === "error") {
    return <PeopleLoadError title={t("The directory didn't load")} />;
  }

  const count = (status: string) =>
    roster.data.filter((employee) => employee.status === status).length;

  return (
    <KpiBand
      kpis={[
        {
          label: t("People"),
          hint: t("Not offboarded"),
          value: String(roster.data.length),
          icon: <UsersIcon className="size-4" />,
        },
        {
          label: t("Active"),
          value: String(count("active")),
          icon: <UserCheckIcon className="size-4" />,
        },
        {
          label: t("Preboarding"),
          hint: t("Hired, not started yet"),
          value: String(count("preboarding")),
          icon: <UserPlusIcon className="size-4" />,
        },
        {
          label: t("On leave"),
          value: String(count("on_leave")),
          icon: <CalendarOffIcon className="size-4" />,
        },
      ]}
    />
  );
}

/** The people grouped by status, one column each. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function EmployeeStatusBoard() {
  await requirePermission("employees.read");

  const [t, roster] = await Promise.all([
    getExtracted("people"),
    settle(getRoster),
  ]);

  if (roster.kind === "no-organization") {
    return null;
  }

  if (roster.kind === "error") {
    return <PeopleLoadError title={t("The directory didn't load")} />;
  }

  const columns = [
    { status: "preboarding", label: t("Preboarding") },
    { status: "active", label: t("Active") },
    { status: "on_leave", label: t("On leave") },
  ];

  return (
    <div className="grid gap-4 md:grid-cols-3">
      {columns.map((column) => {
        const people = roster.data.filter(
          (employee) => employee.status === column.status,
        );

        return (
          <Card key={column.status} size="sm">
            <CardHeader>
              <CardTitle className="flex items-center justify-between gap-2">
                {column.label}
                <Badge variant="secondary">{people.length}</Badge>
              </CardTitle>
            </CardHeader>
            <CardContent className="flex flex-col gap-2 text-sm">
              {people.length === 0 ? (
                <CardDescription>{t("No one here.")}</CardDescription>
              ) : (
                people.map((employee) => (
                  <Link
                    key={employee.id}
                    href={`/people/${employee.id}`}
                    className="flex justify-between gap-2 hover:underline"
                  >
                    <span>{employee.name}</span>
                    <span className="text-muted-foreground">
                      {employee.jobTitle ?? ""}
                    </span>
                  </Link>
                ))
              )}
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}

/**
 * Onboards a new hire onto a program; nothing renders without the right to
 * write.
 */
// skeleton: a button; the page header paints without it
export async function OnboardEmployeeDialog() {
  if (!(await holds("employees.write"))) {
    return null;
  }

  const [t, programs] = await Promise.all([
    getExtracted("people"),
    getOnboardingPrograms(),
  ]);

  if (!programs || programs.length === 0) {
    return null;
  }

  return (
    <ActionDialog
      action={onboardEmployee}
      title={t("Onboard a new hire")}
      description={t(
        "Creates the employee and starts them on an onboarding program.",
      )}
      trigger={t("Onboard")}
      submitLabel={t("Onboard")}
      successMessage={t("Onboarding started")}
      redirectTo="/people/{id}"
      variant="outline"
      fields={[
        { name: "name", label: t("Name"), kind: "text", required: true },
        { name: "email", label: t("Email"), kind: "text" },
        { name: "jobTitle", label: t("Job title"), kind: "text" },
        {
          name: "program",
          label: t("Program"),
          kind: "select",
          required: true,
          options: programs,
        },
        { name: "startDate", label: t("Start date"), kind: "date" },
      ]}
    />
  );
}
