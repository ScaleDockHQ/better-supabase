import { getCarePlan } from "@/features/care-plans/care-plans-queries";
import { CarePlanEditor } from "@/features/care-plans/components/care-plan-editor";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
export async function CarePlanEditorSection() {
  return <CarePlanEditor state={await getCarePlan()} />;
}
