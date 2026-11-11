import { getExtracted } from "next-intl/server";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";

import { getSessions } from "../checkout-sessions-queries";
import { SessionRecordList } from "./session-record-list";

/** Render inside `<Suspense>`; the fallback is `SessionListSkeleton`. */
export async function SessionList() {
  const [page, t] = await Promise.all([
    getSessions(),
    getExtracted("checkoutSessions"),
  ]);

  if (page === null) {
    return (
      <p className="text-sm text-muted-foreground">
        {t("Pick an organization to see its checkout sessions.")}
      </p>
    );
  }

  return (
    <SessionRecordList
      initial={{ items: page.items, nextCursor: page.nextCursor }}
    />
  );
}

export function SessionListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
