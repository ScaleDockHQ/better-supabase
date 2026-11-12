import { getExtracted, getFormatter } from "next-intl/server";
import { forbidden, notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { Badge } from "@/components/reui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

import { getCreditTransaction } from "../credits-queries";

/**
 * Render inside `<Suspense>`; the fallback is
 * `CreditTransactionDetailSkeleton`.
 */
export async function CreditTransactionDetail({ id }: { id: string }) {
  const [transaction, t, format] = await Promise.all([
    getCreditTransaction(id),
    getExtracted("credits"),
    getFormatter(),
  ]);

  if (transaction === "forbidden") {
    forbidden();
  }

  if (!transaction) {
    notFound();
  }

  const labels = new Map([
    ["credit.grant", t("Plan grant")],
    ["credit.purchase", t("Purchase")],
    ["credit.usage", t("Usage")],
  ]);

  return (
    <RecordDetailFrame
      title={transaction.memo ?? t("No description")}
      description={t("{date}, {reference}", {
        date: format.dateTime(new Date(transaction.effectiveAt), {
          dateStyle: "medium",
          timeStyle: "short",
        }),
        reference: transaction.reference ?? "–",
      })}
      status={
        <Badge variant="info-light">
          {labels.get(transaction.kind) ?? transaction.kind}
        </Badge>
      }
    >
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{t("Account")}</TableHead>
            <TableHead className="text-right">{t("Amount")}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {transaction.lines.map((line) => (
            <TableRow key={line.id}>
              <TableCell className="font-medium">{line.account}</TableCell>
              <TableCell className="text-right tabular-nums">
                {format.number(line.amount, { signDisplay: "exceptZero" })}{" "}
                {line.unit}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </RecordDetailFrame>
  );
}

export function CreditTransactionDetailSkeleton() {
  return <Skeleton className="h-48 rounded-xl" aria-busy="true" />;
}
