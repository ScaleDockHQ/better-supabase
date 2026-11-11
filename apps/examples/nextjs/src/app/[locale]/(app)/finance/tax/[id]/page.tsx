import { FinanceDetailPage } from "@/components/finance-pages/finance-pages";

// A navigation here shows the back link and the record's frame at once; the
// record streams in behind the page's boundary.
export const instant = true;

export default function TaxRecordPage({
  params,
}: PageProps<"/[locale]/finance/tax/[id]">) {
  return <FinanceDetailPage entity="tax" ids={params.then(({ id }) => id)} />;
}
