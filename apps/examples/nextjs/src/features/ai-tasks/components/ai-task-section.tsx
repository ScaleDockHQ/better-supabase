import { getAiTasks } from "../ai-tasks-queries";
import { AiTaskQueue } from "./ai-task-queue";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
/** Render inside `<Suspense>`; the fallback is `AiTaskQueueSkeleton`. */
export async function AiTaskSection() {
  const read = await getAiTasks();

  return <AiTaskQueue read={read} />;
}
