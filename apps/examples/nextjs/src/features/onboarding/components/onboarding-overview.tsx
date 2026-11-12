import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { PeopleLoadError } from "@/features/people/components/people-load-error";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { pageBlockRows } from "@/lib/block-list";

import { onboardingList, onboardingSpec } from "../onboarding-list";
import { getOnboarding } from "../onboarding-queries";
import { EnrollEmployeeForm } from "./enroll-employee-form";
import { OnboardingRecordList } from "./onboarding-record-list";
import { SetUpOnboardingButton } from "./setup-onboarding-button";

/**
 * Render inside `<Suspense>`: the onboarding runs of every employee on the list
 * kit, with the enroll form and, for managers with no program, set-up.
 */
export async function OnboardingOverview() {
  const [t, permissions, onboarding] = await Promise.all([
    getExtracted("people"),
    getPermissions(),
    getOnboarding(),
  ]);

  if (!can(permissions, "enrollments.read")) {
    forbidden();
  }

  if (onboarding.kind === "no-organization") {
    return null;
  }

  if (onboarding.kind === "error") {
    return <PeopleLoadError title={t("Onboarding didn't load")} />;
  }

  const { rows, programs, employees } = onboarding.data;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-end gap-2">
        {programs.length === 0 && can(permissions, "enrollments.manage") ? (
          <SetUpOnboardingButton />
        ) : null}
        {programs.length > 0 && can(permissions, "enrollments.enroll") ? (
          <EnrollEmployeeForm
            programs={programs.map((p) => ({ value: p.key, label: p.name }))}
            employees={employees}
          />
        ) : null}
      </div>
      <OnboardingRecordList
        initial={pageBlockRows(
          onboardingList,
          onboardingSpec,
          rows,
          onboardingList.defaults,
        )}
        programs={programs}
      />
    </div>
  );
}

export function OnboardingOverviewSkeleton() {
  return <RecordListSkeleton rows={5} />;
}
