import { ShieldIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";

import { getRoles } from "../roles-queries";
import { RolesGrid } from "./roles-grid";

/** Render inside `<Suspense>`; the fallback is `RolesSectionSkeleton`. */
export async function RolesSection() {
  const [roles, t] = await Promise.all([getRoles(), getExtracted("roles")]);

  return (
    <Frame spacing="sm">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Roles")}</FrameTitle>
        <FrameDescription>
          {t(
            "Every organization starts from the catalog's roles. Override a role's keys here; the change applies in this organization only.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {roles === null || roles.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ShieldIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No roles")}</EmptyTitle>
              <EmptyDescription>
                {t("The permissions catalog lists no tenant roles.")}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <RolesGrid
            roles={roles.map((role) => ({
              id: role.id,
              key: role.key,
              members: role.members,
              permissions: role.permissions.length,
              overrides: role.overrides.length,
            }))}
          />
        )}
      </FramePanel>
    </Frame>
  );
}

export function RolesSectionSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-20" />
        <Skeleton className="h-4 w-72" />
      </FrameHeader>
      <FramePanel>
        <Skeleton className="h-40" />
      </FramePanel>
    </Frame>
  );
}
