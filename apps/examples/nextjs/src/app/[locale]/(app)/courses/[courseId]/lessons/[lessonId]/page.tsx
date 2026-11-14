import { Suspense } from "react";

import {
  LessonPlayer,
  LessonPlayerSkeleton,
} from "@/features/courses/components/lesson-player";
import { PermissionGate } from "@/features/user/components/permission-gate";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function LessonPage({
  params,
}: PageProps<"/[locale]/courses/[courseId]/lessons/[lessonId]">) {
  return (
    <Suspense fallback={<LessonPlayerSkeleton />}>
      <PermissionGate permission="courses.read">
        {params.then(({ courseId, lessonId }) => (
          <LessonPlayer courseId={courseId} lessonId={lessonId} />
        ))}
      </PermissionGate>
    </Suspense>
  );
}
