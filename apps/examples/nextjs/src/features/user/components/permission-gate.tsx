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

import type { Permission } from "../user-permissions";

import { getPermissions } from "../permission-snapshot";
import { can } from "../user-permissions";

/**
 * Renders `children` only when the session has `permission`. UI only: the data
 * behind it is still protected by RLS and by each Server Action. The keys come
 * from the token, so the children wait on a `my_permissions` read only when the
 * hook marked the claim truncated.
 */
export async function PermissionGate({
  permission,
  children,
}: {
  permission: Permission;
  children: ReactNode;
}) {
  const [t, permissions] = await Promise.all([
    getExtracted("user"),
    getPermissions(),
  ]);

  if (can(permissions, permission)) {
    return children;
  }

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
