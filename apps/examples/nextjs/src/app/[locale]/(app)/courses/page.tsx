import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { KpiBandSkeleton } from "@/components/record-list/kpi-band";
import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import {
  activeView,
  RecordViewSwitch,
} from "@/components/record-list/record-view-switch";
import {
  CourseList,
  CourseListSkeleton,
} from "@/features/courses/components/course-list";
import {
  CourseKpis,
  CourseTable,
} from "@/features/courses/components/course-overviews";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/block-overview-query";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function CoursesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("courses");

  return (
    <>
      <PageHeader
        title={t("Courses")}
        description={t("Take the courses your organization publishes.")}
      />
      <Suspense fallback={<CourseListSkeleton />}>
        {searchParams.then((raw) => {
          const views = ["board", "table"] as const;
          const view = activeView(raw, views);

          return (
            <>
              <RecordViewSwitch base="/courses" active={view} views={views} />
              <Suspense fallback={<KpiBandSkeleton />}>
                <PermissionGate permission="courses.read">
                  <CourseKpis />
                </PermissionGate>
              </Suspense>
              {view === "table" ? (
                <Suspense fallback={<RecordListSkeleton rows={4} />}>
                  <CourseTable query={parseBlockList(raw)} />
                </Suspense>
              ) : (
                <Suspense fallback={<CourseListSkeleton />}>
                  <PermissionGate permission="courses.read">
                    <CourseList />
                  </PermissionGate>
                </Suspense>
              )}
            </>
          );
        })}
      </Suspense>
    </>
  );
}
