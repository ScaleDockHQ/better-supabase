import { UsersIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";

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
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { loadDirectory, settle } from "../people-queries";
import { AddEmployeeDialog } from "./add-employee-dialog";
import { EmployeeTable } from "./employee-table";
import { PeopleLoadError } from "./people-load-error";

// #region recipe:employee-directory
/**
 * Render inside `<Suspense>`: the employees as an org chart, each manager above
 * their reports, with a search. Private details open in a sheet for callers
 * with `employees.view_sensitive`.
 */
export async function EmployeeDirectory() {
  const [t, permissions] = await Promise.all([
    getExtracted("people"),
    getPermissions(),
  ]);

  if (!can(permissions, "employees.read")) {
    forbidden();
  }

  const directory = await settle(loadDirectory);

  if (directory.kind === "no-organization") {
    return null;
  }

  const canWrite = can(permissions, "employees.write");
  const canViewSensitive = can(permissions, "employees.view_sensitive");

  const managers =
    directory.kind === "ok"
      ? directory.data.map((employee) => ({
          value: employee.id,
          label: employee.name,
        }))
      : [];

  const addEmployee = canWrite ? (
    <AddEmployeeDialog
      managers={managers}
      canViewSensitive={canViewSensitive}
    />
  ) : null;

  return (
    <Card data-recipe="employee-directory">
      <CardHeader>
        <CardTitle>{t("Employees")}</CardTitle>
        <CardDescription>
          {t("Everyone in the organization and who they report to.")}
        </CardDescription>
        {addEmployee && managers.length > 0 ? (
          <CardAction>{addEmployee}</CardAction>
        ) : null}
      </CardHeader>
      <CardContent>
        {directory.kind === "error" ? (
          <PeopleLoadError title={t("The directory didn't load")} />
        ) : directory.data.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <UsersIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No employees yet")}</EmptyTitle>
              <EmptyDescription>
                {canWrite
                  ? t("Add the first employee to start the org chart.")
                  : t("Ask an admin to add employees.")}
              </EmptyDescription>
            </EmptyHeader>
            {addEmployee ? <EmptyContent>{addEmployee}</EmptyContent> : null}
          </Empty>
        ) : (
          <EmployeeTable
            employees={directory.data}
            canViewSensitive={canViewSensitive}
          />
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:employee-directory

export function EmployeeDirectorySkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}
