import { Suspense } from "react";

import {
  CustomFieldsEditor,
  CustomFieldsEditorSkeleton,
} from "@/features/custom-fields/components/custom-fields-editor";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

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
