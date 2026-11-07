import { InspectionProgramCalendar } from "@/features/inspections/components/inspection-program-calendar";
import { getInspectionCalendar } from "@/features/inspections/inspections-queries";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
export async function InspectionProgramCalendarSection() {
  return <InspectionProgramCalendar state={await getInspectionCalendar()} />;
}
