import { getExtracted } from "next-intl/server";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getGiftFormOptions, getGifts } from "../donations-queries";
import { GiftRecordList } from "./gift-record-list";

/** Render inside `<Suspense>`; the fallback is `GiftListSkeleton`. */
export async function GiftList() {
  const [page, permissions, t] = await Promise.all([
    getGifts(),
    getPermissions(),
    getExtracted("donations"),
  ]);

  if (page === null) {
    return (
      <p className="text-sm text-muted-foreground">
        {t("Pick an organization to see its gifts.")}
      </p>
    );
  }

  const canManage = can(permissions, "donations.manage");

  return (
    <GiftRecordList
      initial={{ items: page.items, nextCursor: page.nextCursor }}
      canManage={canManage}
      options={canManage ? await getGiftFormOptions() : null}
    />
  );
}

export function GiftListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
