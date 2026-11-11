import { getExtracted } from "next-intl/server";

import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getToolAccess } from "../agents-queries";
import { ToolAccessMatrix } from "./tool-access-matrix";

/** Render inside `<Suspense>`: the tools with their rules for the organization. */
export async function ToolAccess() {
  const [read, permissions, t] = await Promise.all([
    getToolAccess(),
    getPermissions(),
    getExtracted("agents"),
  ]);

  if (!read.ok) {
    return (
      <Alert variant="destructive">
        <AlertTitle>{t("The rules did not load")}</AlertTitle>
        <AlertDescription>{read.error.message}</AlertDescription>
      </Alert>
    );
  }

  return (
    <ToolAccessMatrix
      rows={read.rows}
      canManage={can(permissions, "ai_chat.manage")}
    />
  );
}

export function ToolAccessSkeleton() {
  return (
    <div className="flex flex-col gap-2" aria-busy="true">
      <Skeleton className="h-14 w-full" />
      <Skeleton className="h-14 w-full" />
      <Skeleton className="h-14 w-full" />
    </div>
  );
}
