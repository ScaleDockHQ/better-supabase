import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { pageBlockRows } from "@/lib/block-list";

import { movementList, movementSpec } from "../inventory-list";
import { getMovements } from "../inventory-queries";
import { InventoryLoadError } from "./inventory-load-error";
import { MovementRecordList } from "./movement-record-list";

/** Render inside `<Suspense>`: the newest ledger movements on the list kit. */
export async function MovementsOverview() {
  const [t, permissions, movements] = await Promise.all([
    getExtracted("inventory"),
    getPermissions(),
    getMovements(),
  ]);

  if (!can(permissions, "inventory.read")) {
    forbidden();
  }

  if (movements.kind === "no-organization") {
    return null;
  }

  if (movements.kind === "error") {
    return <InventoryLoadError title={t("The movements didn't load")} />;
  }

  return (
    <MovementRecordList
      initial={pageBlockRows(
        movementList,
        movementSpec,
        movements.data.rows,
        movementList.defaults,
      )}
      locations={movements.data.locations}
    />
  );
}

export function MovementsOverviewSkeleton() {
  return <RecordListSkeleton rows={6} />;
}
