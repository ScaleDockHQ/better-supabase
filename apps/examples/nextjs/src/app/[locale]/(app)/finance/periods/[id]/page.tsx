import { FinanceDetailPage } from "@/components/finance-pages/finance-pages";

// A navigation here shows the back link and the record's frame at once; the
// record streams in behind the page's boundary.
export const instant = true;

export default function PeriodsRecordPage({
  params,
}: PageProps<"/[locale]/finance/periods/[id]">) {
  return (
    <FinanceDetailPage
      entity="periods"
      ids={params.then(({ id }) => id)}
    />
  );
}
