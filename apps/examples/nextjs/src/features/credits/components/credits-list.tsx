import { getExtracted, getFormatter } from "next-intl/server";
import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

import { getCreditBalance, getCreditEntries } from "../credits-queries";
import { CreditRecordList } from "./credits-record-list";

/** Render inside `<Suspense>`; the fallback is `CreditListSkeleton`. */
export async function CreditList() {
  const [page, balance, t, format] = await Promise.all([
    getCreditEntries(),
    getCreditBalance(),
    getExtracted("credits"),
    getFormatter(),
  ]);

  if (!page || !balance) {
    forbidden();
  }

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <CardDescription>{t("Credit balance")}</CardDescription>
          <CardTitle className="text-2xl tabular-nums">
            {format.number(balance.balance)}
          </CardTitle>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground">
          {t("{held, number} credits are held for running work.", {
            held: balance.held,
          })}
        </CardContent>
      </Card>
      <CreditRecordList initial={page} />
    </div>
  );
}

export function CreditListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
