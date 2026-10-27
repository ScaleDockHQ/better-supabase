import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  CourseList,
  CourseListSkeleton,
} from "@/features/courses/components/course-list";
import { PermissionGate } from "@/features/user/components/permission-gate";

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
