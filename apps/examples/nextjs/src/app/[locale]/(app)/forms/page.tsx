import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  FormList,
  FormListSkeleton,
  FormManagerActions,
} from "@/features/forms/components/form-list";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function FormsPage() {
  const t = useExtracted("forms");

  return (
    <>
      <PageHeader
        title={t("Forms")}
        description={t("Build forms and read the responses.")}
        actions={
          <Suspense fallback={null}>
            <FormManagerActions />
          </Suspense>
        }
      />
      <Suspense fallback={<FormListSkeleton />}>
        <PermissionGate permission="forms.read">
          <FormList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
