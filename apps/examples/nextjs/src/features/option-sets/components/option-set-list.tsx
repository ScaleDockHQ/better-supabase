import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getOptionSets } from "../option-sets-queries";
import { OptionSetRecordList } from "./option-set-record-list";

/** Render inside `<Suspense>`; the fallback is `OptionSetListSkeleton`. */
export async function OptionSetList() {
  const [page, permissions] = await Promise.all([
    getOptionSets(),
    getPermissions(),
  ]);

  if (!page || !can(permissions, "option_sets.read")) {
    forbidden();
  }

  return (
    <OptionSetRecordList
      initial={page}
      canManage={can(permissions, "option_sets.manage")}
    />
  );
}

export function OptionSetListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
