import type { ReactNode } from "react";

import { tenantOf } from "better-supabase/next";
import {
  ActivityIcon,
  UserPlusIcon,
  UsersIcon,
  UsersRoundIcon,
} from "lucide-react";
import { getExtracted } from "next-intl/server";

import { Card, CardDescription, CardHeader } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getMembers } from "@/features/organization/organization-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { getWorkspaceSummary } from "../dashboard-queries";

function Stat({
  label,
  value,
  icon,
}: {
  label: string;
  value: ReactNode;
  icon: ReactNode;
}) {
  return (
    <Card size="sm">
      <CardHeader>
        <CardDescription className="flex items-center justify-between">
          {label}
          <span className="text-muted-foreground [&>svg]:size-4">{icon}</span>
        </CardDescription>
        <p className="truncate text-2xl font-semibold tracking-tight tabular-nums">
          {value}
        </p>
      </CardHeader>
    </Card>
  );
}

/** Render inside `<Suspense>`; the fallback is `WorkspaceSummarySkeleton`. */
export async function WorkspaceSummary() {
  const [summary, t, session, permissions] = await Promise.all([
    getWorkspaceSummary(),
    getExtracted("dashboard"),
    getSession(),
    getPermissions(),
  ]);

  if (!summary) {
    return null;
  }

  const tenant = tenantOf(session);

  const members =
    tenant && can(permissions, "members.read")
      ? (await getMembers(tenant)).length
      : undefined;

  return (
    <div
      className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4"
      data-testid="workspace-summary"
    >
      <Stat
        label={t("Customers")}
        value={summary.customers}
        icon={<UsersIcon />}
      />
      <Stat
        label={t("Active")}
        value={summary.active}
        icon={<ActivityIcon />}
      />
      <Stat
        label={t("Added by you")}
        value={summary.mine}
        icon={<UserPlusIcon />}
      />
      <Stat
        label={t("Members")}
        value={members ?? "–"}
        icon={<UsersRoundIcon />}
      />
    </div>
  );
}

export function WorkspaceSummarySkeleton() {
  return (
    <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4" aria-busy="true">
      {Array.from({ length: 4 }, (_, index) => (
        <Skeleton key={index} className="h-24 rounded-xl" />
      ))}
    </div>
  );
}
