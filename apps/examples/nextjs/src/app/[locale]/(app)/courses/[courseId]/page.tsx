import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
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
        <PermissionGate permission="courses.read">
          {params.then(({ courseId }) => (
            <CourseOutline courseId={courseId} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
