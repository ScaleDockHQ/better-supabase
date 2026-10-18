import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  EmployeeDirectory,
  EmployeeDirectorySkeleton,
} from "@/features/people/components/employee-directory";

export const instant = true;

export default function PeoplePage() {
  const t = useExtracted("people");

  return (
    <>
      <PageHeader
        title={t("People")}
        description={t("Your organization's employees and who they report to.")}
      />
      <Suspense fallback={<EmployeeDirectorySkeleton />}>
        <EmployeeDirectory />
      </Suspense>
    </>
  );
}
