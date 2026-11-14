import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  CourseList,
  CourseListSkeleton,
} from "@/features/courses/components/course-list";
import { PermissionGate } from "@/features/user/components/permission-gate";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function CoursesPage() {
  const t = useExtracted("courses");

  return (
    <>
      <PageHeader
        title={t("Courses")}
        description={t("Take the courses your organization publishes.")}
      />
      <Suspense fallback={<CourseListSkeleton />}>
        <PermissionGate permission="courses.read">
          <CourseList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
