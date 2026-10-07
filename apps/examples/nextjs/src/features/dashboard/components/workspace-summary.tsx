import type { ReactNode } from "react";

import {
  ActivityIcon,
  NotebookPenIcon,
  UserPlusIcon,
  UsersIcon,
} from "lucide-react";
import { getExtracted } from "next-intl/server";

import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

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
        <CardTitle className="truncate text-2xl tabular-nums">
          {value}
        </CardTitle>
      </CardHeader>
    </Card>
  );
}

/** Render inside `<Suspense>`; the fallback is `WorkspaceSummarySkeleton`. */
export async function WorkspaceSummary() {
  const summary = await getWorkspaceSummary();
  if (!summary) return null;
  const t = await getExtracted("dashboard");
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
        label={t("Latest note")}
        value={
          <span className="text-base font-medium">
            {summary.latestNote?.body ?? t("None yet")}
          </span>
        }
        icon={<NotebookPenIcon />}
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
