import { FinanceDetailPage } from "@/components/finance-pages/finance-pages";

// A navigation here shows the back link and the record's frame at once; the
// record streams in behind the page's boundary.
export const instant = true;

export default function JournalRecordPage({
  params,
}: PageProps<"/[locale]/finance/accounting/[id]">) {
  return (
    <FinanceDetailPage entity="journal" ids={params.then(({ id }) => id)} />
  );
}
