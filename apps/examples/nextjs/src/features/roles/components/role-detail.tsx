import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";
import * as v from "valibot";

import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { KpiBand } from "@/components/record-list/kpi-band";
import { Alert, AlertDescription } from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Role } from "@/lib/claims";

import { assignableRoles, getRoles } from "../roles-queries";
import { PermissionMatrix } from "./permission-matrix";

/**
 * Render inside `<Suspense>`: one catalog role's keys in the organization. The
 * owner role stays read-only, and a caller changes only roles they could assign
 * and keys they hold, the rules `set_permission_override` applies.
 */
export async function RoleDetail({ roleId }: { roleId: string }) {
  const [roles, held, t, organization] = await Promise.all([
    getRoles(),
    getPermissions(),
    getExtracted("roles"),
    getExtracted("organization"),
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

  const added = role.permissions.filter(
    (key) => !role.defaultPermissions.includes(key),
  ).length;

  const removed = role.defaultPermissions.filter(
    (key) => !role.permissions.includes(key),
  ).length;

  const label = v.is(Role, role.key)
    ? {
        owner: organization("Owner"),
        admin: organization("Admin"),
        member: organization("Member"),
      }[role.key]
    : role.key;

  return (
    <div data-testid="role-detail">
      <RecordDetailFrame
        title={label}
        description={t(
          "{members, plural, one {# member} other {# members}} · {count, number} of {total, number} permissions",
          {
            members: role.members,
            count: role.permissions.length,
            total: keys.length,
          },
        )}
        status={
          added + removed === 0 ? (
            <Badge variant="secondary">{t("Default")}</Badge>
          ) : (
            <Badge variant="warning-light">{t("Customised")}</Badge>
          )
        }
        aside={
          <PropertiesRail
            title={t("Properties")}
            properties={[
              { label: t("Key"), value: role.key },
              { label: t("Members"), value: String(role.members) },
              {
                label: t("Permissions"),
                value: `${role.permissions.length} / ${keys.length}`,
              },
              { label: t("Editable"), value: editable ? t("Yes") : t("No") },
            ]}
          />
        }
      >
        <KpiBand
          kpis={[
            { label: t("Members"), value: String(role.members) },
            { label: t("Permissions"), value: String(role.permissions.length) },
            { label: t("Added to the default"), value: String(added) },
            { label: t("Removed from the default"), value: String(removed) },
          ]}
        />
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
        <Card>
          <CardHeader>
            <CardTitle>{t("Permission matrix")}</CardTitle>
            <CardDescription>
              {t("Every key the organization's roles use, grouped by module.")}
            </CardDescription>
          </CardHeader>
          <CardContent>
            <PermissionMatrix
              roleId={role.id}
              keys={keys}
              defaults={role.defaultPermissions}
              effective={role.permissions}
              held={held}
              editable={editable}
            />
          </CardContent>
        </Card>
      </RecordDetailFrame>
    </div>
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
