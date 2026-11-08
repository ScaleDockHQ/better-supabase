import { Suspense } from "react";

import {
  CustomFieldsEditor,
  CustomFieldsEditorSkeleton,
} from "@/features/custom-fields/components/custom-fields-editor";

export default function CustomFieldsSettingsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  return (
    <Suspense fallback={<CustomFieldsEditorSkeleton />}>
      {searchParams.then((query) => (
        <CustomFieldsEditor query={query} />
      ))}
    </Suspense>
  );
}
