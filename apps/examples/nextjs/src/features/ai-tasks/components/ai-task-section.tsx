import { getAiTasks } from "../ai-task-queries";
import { AiTaskQueue } from "./ai-task-queue";

/** Render inside `<Suspense>`; the fallback is `AiTaskQueueSkeleton`. */
export async function AiTaskSection() {
  const read = await getAiTasks();

  return <AiTaskQueue read={read} />;
}
