import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getIncomingWebhooks } from "../incoming-webhooks-queries";
import { CreateIncomingWebhookDialog } from "./incoming-webhook-controls";
import { IncomingWebhookRecordList } from "./incoming-webhook-record-list";

/** Render inside `<Suspense>`; the fallback is `IncomingWebhookListSkeleton`. */
export async function IncomingWebhookList() {
  const [page, permissions] = await Promise.all([
    getIncomingWebhooks(),
    getPermissions(),
  ]);

  if (!page || !can(permissions, "webhooks.read")) {
    forbidden();
  }

  const manage = can(permissions, "webhooks.manage");

  return (
    <div className="flex flex-col gap-4">
      {manage ? (
        <div className="flex justify-end">
          <CreateIncomingWebhookDialog />
        </div>
      ) : null}
      <IncomingWebhookRecordList initial={page} canManage={manage} />
    </div>
  );
}

export function IncomingWebhookListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
