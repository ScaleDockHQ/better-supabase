import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";

import { getOAuthApps } from "../oauth-apps-queries";
import { OAuthAppRecordList } from "./oauth-apps-record-list";

/** Render inside `<Suspense>`; the fallback is `OAuthAppListSkeleton`. */
export async function OAuthAppList() {
  const page = await getOAuthApps();

  if (!page) {
    forbidden();
  }

  return <OAuthAppRecordList initial={page} />;
}

export function OAuthAppListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
