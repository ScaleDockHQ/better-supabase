import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

import { getAiTasks } from "../ai-tasks-queries";
import { AiTaskQueue } from "./ai-task-queue";

const SKELETON_ROWS = ["first", "second", "third"];

/** Render inside `<Suspense>`; the fallback is `AiTaskQueueSkeleton`. */
export async function AiTaskSection() {
  const read = await getAiTasks();

  return <AiTaskQueue read={read} />;
}

export function AiTaskSectionSkeleton() {
  return (
    <Card aria-busy="true">
      <CardHeader>
        <Skeleton className="h-5 w-40" />
        <Skeleton className="h-4 w-72" />
      </CardHeader>
      <CardContent className="flex flex-col gap-2">
        {SKELETON_ROWS.map((row) => (
          <Skeleton key={row} className="h-11 w-full" />
        ))}
      </CardContent>
    </Card>
  );
}
