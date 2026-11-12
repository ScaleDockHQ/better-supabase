import type { ReactNode } from "react";

import { formatMoney, moneyFromJson } from "better-supabase/commerce";
import { getExtracted, getFormatter, getLocale } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getGift } from "../donations-queries";
import { GiftStatusBadge } from "./gift-status";
import { IssueReceiptButton } from "./issue-receipt-button";

/** One gift with its fund, method and receipt. */
export async function GiftDetail({ id }: { id: string }): Promise<ReactNode> {
  const [gift, permissions, t, format, locale] = await Promise.all([
    getGift(id),
    getPermissions(),
    getExtracted("donations"),
    getFormatter(),
    getLocale(),
  ]);

  if (gift === null) {
    notFound();
  }

  return (
    <RecordDetailFrame
      title={t("Gift from {donor}", { donor: gift.donor })}
      description={formatMoney(moneyFromJson(gift.amount), locale)}
      status={<GiftStatusBadge status={gift.status} />}
      actions={
        gift.status === "posted" &&
        !gift.hasReceipt &&
        can(permissions, "donations.manage") ? (
          <IssueReceiptButton giftId={gift.id} />
        ) : null
      }
    >
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Details")}</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-2 gap-2 text-sm">
          <span className="text-muted-foreground">{t("Received")}</span>
          <span className="text-right">
            {format.dateTime(new Date(gift.receivedOn), {
              dateStyle: "medium",
            })}
          </span>
          <span className="text-muted-foreground">{t("Fund")}</span>
          <span className="text-right">{gift.fund ?? "–"}</span>
          <span className="text-muted-foreground">{t("Method")}</span>
          <span className="text-right">{gift.method ?? "–"}</span>
          <span className="text-muted-foreground">{t("Receipt")}</span>
          <span className="text-right">
            {gift.receiptNumber ?? (gift.hasReceipt ? t("Issued") : "–")}
          </span>
          {gift.note ? (
            <>
              <span className="text-muted-foreground">{t("Note")}</span>
              <span className="text-right">{gift.note}</span>
            </>
          ) : null}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function GiftDetailSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-10 w-72" />
      <RecordSectionSkeleton rows={4} />
    </div>
  );
}
