import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";
import * as v from "valibot";

import { Alert, AlertDescription } from "@/components/reui/alert";
import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Role } from "@/lib/claims";

import { assignableRoles, getRoles } from "../roles-queries";
import { PermissionMatrix } from "./permission-matrix";
import { RoleName } from "./role-name";

/**
 * Render inside `<Suspense>`: one catalog role's keys in the organization. The
 * owner role stays read-only, and a caller changes only roles they could assign
 * and keys they hold, the rules `set_permission_override` applies.
 */
export async function RoleDetail({
  params,
}: {
  params: Promise<{ roleId: string }>;
}) {
  const [{ roleId }, roles, held, t] = await Promise.all([
    params,
    getRoles(),
    getPermissions(),
    getExtracted("roles"),
  ]);

  const role = roles?.find((each) => each.id === roleId);

  if (!roles || !role) {
    notFound();
  }

  const keys = [
    ...new Set(
      roles.flatMap((each) => [
        ...each.defaultPermissions,
        ...each.permissions,
      ]),
    ),
  ].toSorted();

  const assignable = assignableRoles(roles, held);

  const editable =
    role.key !== "owner" &&
    can(held, "roles.manage") &&
    v.is(Role, role.key) &&
    assignable.includes(role.key);

  return (
    <Frame spacing="sm" data-testid="role-detail">
      <FrameHeader className="gap-0.5">
        <FrameTitle>
          <RoleName roleKey={role.key} />
        </FrameTitle>
        <FrameDescription>
          {t(
            "{members, plural, one {# member} other {# members}} · {count, number} of {total, number} permissions",
            {
              members: role.members,
              count: role.permissions.length,
              total: keys.length,
            },
          )}
        </FrameDescription>
      </FrameHeader>
      {editable ? null : (
        <Alert variant="info">
          <AlertDescription>
            {role.key === "owner"
              ? t("The owner role holds every permission and can't change.")
              : t(
                  "You can read this role. Changing it needs the roles.manage permission and every key it holds.",
                )}
          </AlertDescription>
        </Alert>
      )}
      <FramePanel>
        <PermissionMatrix
          roleId={role.id}
          keys={keys}
          defaults={role.defaultPermissions}
          effective={role.permissions}
          held={held}
          editable={editable}
        />
      </FramePanel>
    </Frame>
  );
}

export function RoleDetailSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-24" />
        <Skeleton className="h-4 w-56" />
      </FrameHeader>
      <FramePanel className="flex flex-col gap-3">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-72" />
      </FramePanel>
    </Frame>
  );
}
