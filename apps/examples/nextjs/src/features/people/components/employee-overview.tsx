import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { pageBlockRows } from "@/lib/block-list";

import { employeeList, employeeSpec } from "../employees-list";
import { loadDirectory, settle } from "../people-queries";
import { AddEmployeeDialog } from "./add-employee-dialog";
import { EmployeeRecordList } from "./employee-record-list";
import { PeopleLoadError } from "./people-load-error";

// #region recipe:employee-directory
/**
 * Render inside `<Suspense>`: every employee on the list kit, with the add
 * action for callers who can write.
 */
export async function EmployeeOverview() {
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

  if (directory.kind === "error") {
    return <PeopleLoadError title={t("The directory didn't load")} />;
  }

  const managers = directory.data.map((employee) => ({
    value: employee.id,
    label: employee.name,
  }));

  return (
    <div className="flex flex-col gap-4">
      {can(permissions, "employees.write") ? (
        <div className="flex justify-end">
          <AddEmployeeDialog
            managers={managers}
            canViewSensitive={can(permissions, "employees.read_sensitive")}
          />
        </div>
      ) : null}
      <EmployeeRecordList
        initial={pageBlockRows(
          employeeList,
          employeeSpec,
          directory.data,
          employeeList.defaults,
        )}
      />
    </div>
  );
}

// #endregion recipe:employee-directory

export function EmployeeOverviewSkeleton() {
  return <RecordListSkeleton rows={6} />;
}
