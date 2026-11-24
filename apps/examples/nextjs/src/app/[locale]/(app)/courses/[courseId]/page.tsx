import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { RecordBoundSections } from "@/components/record-detail/record-bound-sections";
import {
  activeTab,
  RecordDetailTabs,
} from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  CourseLearners,
  CourseLearnersSkeleton,
} from "@/features/courses/components/course-learners";
import {
  CourseOutline,
  CourseOutlineSkeleton,
} from "@/features/courses/components/course-outline";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

/** The back link is the static shell; the outline streams in. */
// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function CoursePage({
  params,
  searchParams,
}: PageProps<"/[locale]/courses/[courseId]">) {
  const t = useExtracted("courses");

  return (
    <>
      <Link
        href="/courses"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All courses")}
      </Link>
      <Suspense fallback={<CourseOutlineSkeleton />}>
        {Promise.all([params, searchParams]).then(([{ courseId }, raw]) => {
          const tab = activeTab(raw, ["outline", "enrollments", "activity"]);
          const subject = { type: "course", id: courseId } as const;

          return (
            <>
              <RecordDetailTabs
                base={`/courses/${courseId}`}
                active={tab}
                tabs={[
                  { value: "outline", label: t("Outline") },
                  { value: "enrollments", label: t("Enrollments") },
                  { value: "activity", label: t("Activity") },
                ]}
              />
              <PermissionGate permission="courses.read">
                {tab === "enrollments" ? (
                  <Suspense fallback={<CourseLearnersSkeleton />}>
                    <CourseLearners courseId={courseId} />
                  </Suspense>
                ) : tab === "activity" ? (
                  <RecordBoundSections
                    subject={subject}
                    sections={["discussion", "history", "files"]}
                  />
                ) : (
                  <CourseOutline courseId={courseId} />
                )}
              </PermissionGate>
            </>
          );
        })}
      </Suspense>
    </>
  );
}
