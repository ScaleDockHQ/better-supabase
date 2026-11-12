import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { pageBlockRows } from "@/lib/block-list";

import { lotList, lotSpec } from "../inventory-list";
import { getLots } from "../inventory-queries";
import { InventoryLoadError } from "./inventory-load-error";
import { LotRecordList } from "./lot-record-list";

/** Render inside `<Suspense>`: the lots with stock and an expiry date. */
export async function LotsOverview() {
  const [t, permissions, lots] = await Promise.all([
    getExtracted("inventory"),
    getPermissions(),
    getLots(),
  ]);

  if (!can(permissions, "inventory.read")) {
    forbidden();
  }

  if (lots.kind === "no-organization") {
    return null;
  }

  if (lots.kind === "error") {
    return <InventoryLoadError title={t("The lots didn't load")} />;
  }

  return (
    <LotRecordList
      initial={pageBlockRows(
        lotList,
        lotSpec,
        lots.data.rows,
        lotList.defaults,
      )}
      locations={lots.data.locations}
    />
  );
}

export function LotsOverviewSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
