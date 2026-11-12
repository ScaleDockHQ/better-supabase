import { FinanceDetailPage } from "@/components/finance-pages/finance-pages";

// A navigation here shows the back link and the record's frame at once; the
// record streams in behind the page's boundary.
export const instant = true;

export default function BillableTimeRecordPage({
  params,
}: PageProps<"/[locale]/finance/billable-time/[id]">) {
  return (
    <FinanceDetailPage
      entity="billable-time"
      ids={params.then(({ id }) => id)}
    />
  );
}
