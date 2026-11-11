import { FinanceDetailPage } from "@/components/finance-pages/finance-pages";

// A navigation here shows the back link and the record's frame at once; the
// record streams in behind the page's boundary.
export const instant = true;

export default function ExpensesRecordPage({
  params,
}: PageProps<"/[locale]/finance/expenses/[id]">) {
  return (
    <FinanceDetailPage
      entity="expenses"
      ids={params.then(({ id }) => id)}
    />
  );
}
