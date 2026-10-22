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

export const instant = true;

/** The back link is the static shell; the outline streams in. */
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
          <CourseOutline params={params} />
        </PermissionGate>
      </Suspense>
    </>
  );
}
