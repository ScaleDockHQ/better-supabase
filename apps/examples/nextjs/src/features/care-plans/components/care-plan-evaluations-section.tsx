import { getCarePlan } from "@/features/care-plans/care-plans-queries";
import { CarePlanEvaluations } from "@/features/care-plans/components/care-plan-evaluations";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
export async function CarePlanEvaluationsSection() {
  return <CarePlanEvaluations state={await getCarePlan()} />;
}
