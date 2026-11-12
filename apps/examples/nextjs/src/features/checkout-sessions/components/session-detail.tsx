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
import { Link } from "@/i18n/navigation";

import { getSession } from "../checkout-sessions-queries";
import { SessionActionsBar } from "./session-actions-bar";
import { SessionStatusBadge } from "./session-status";

/** One session with its buyer details, cart total and order. */
export async function SessionDetail({
  id,
}: {
  id: string;
}): Promise<ReactNode> {
  const [session, permissions, t, format, locale] = await Promise.all([
    getSession(id),
    getPermissions(),
    getExtracted("checkoutSessions"),
    getFormatter(),
    getLocale(),
  ]);

  if (session === null) {
    notFound();
  }

  const open = session.status === "open" || session.status === "ready";

  return (
    <RecordDetailFrame
      title={t("Session {id}", { id: session.id.slice(0, 8) })}
      description={
        session.total === null
          ? ""
          : formatMoney(moneyFromJson(session.total), locale)
      }
      status={
        <SessionStatusBadge status={session.status} expired={session.expired} />
      }
      actions={
        open && can(permissions, "agent_checkout.write") ? (
          <SessionActionsBar sessionId={session.id} />
        ) : null
      }
    >
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Details")}</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-2 gap-2 text-sm">
          <span className="text-muted-foreground">{t("Protocol")}</span>
          <span className="text-right">{session.protocol.toUpperCase()}</span>
          <span className="text-muted-foreground">{t("Started")}</span>
          <span className="text-right">
            {format.dateTime(new Date(session.createdAt), {
              dateStyle: "medium",
              timeStyle: "short",
            })}
          </span>
          <span className="text-muted-foreground">{t("Expires")}</span>
          <span className="text-right">
            {session.expiresAt === null
              ? "–"
              : format.dateTime(new Date(session.expiresAt), {
                  dateStyle: "medium",
                  timeStyle: "short",
                })}
          </span>
          <span className="text-muted-foreground">{t("Order")}</span>
          <span className="text-right">
            {session.orderId === null ? (
              "–"
            ) : (
              <Link
                href={`/shop/orders/${session.orderId}`}
                className="hover:underline"
              >
                {session.orderId.slice(0, 8)}
              </Link>
            )}
          </span>
          {session.buyerDetails.map(([key, value]) => (
            <div key={key} className="contents">
              <span className="text-muted-foreground">{key}</span>
              <span className="text-right">{value}</span>
            </div>
          ))}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function SessionDetailSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-10 w-72" />
      <RecordSectionSkeleton rows={4} />
    </div>
  );
}
