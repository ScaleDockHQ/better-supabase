import { Suspense } from "react";

import {
  LessonPlayer,
  LessonPlayerSkeleton,
} from "@/features/courses/components/lesson-player";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function LessonPage({
  params,
}: PageProps<"/[locale]/courses/[courseId]/lessons/[lessonId]">) {
  return (
    <Suspense fallback={<LessonPlayerSkeleton />}>
      <PermissionGate permission="courses.read">
        <LessonPlayer params={params} />
      </PermissionGate>
    </Suspense>
  );
}
