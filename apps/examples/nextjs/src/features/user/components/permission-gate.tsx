import type { ReactNode } from "react";

import { LockIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";

import { type Permission, can } from "../user-permissions";
import { getSession } from "../user-queries";

/**
 * Renders `children` only when the session has `permission`. UI only: the
 * data behind it is still protected by RLS and by each Server Action.
 */
export async function PermissionGate({
  permission,
  children,
}: {
  permission: Permission;
  children: ReactNode;
}) {
  const [session, t] = await Promise.all([getSession(), getExtracted("user")]);
  if (can(session, permission)) return children;
  return (
    <Empty role="alert" className="border">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <LockIcon />
        </EmptyMedia>
        <EmptyTitle>{t("You don't have access")}</EmptyTitle>
        <EmptyDescription>
          {t("This needs the {permission} permission in this organization.", {
            permission,
          })}
        </EmptyDescription>
      </EmptyHeader>
    </Empty>
  );
}
