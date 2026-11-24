import {
  CalendarCheckIcon,
  CalendarClockIcon,
  CalendarOffIcon,
} from "lucide-react";
import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";

import { KpiBand } from "@/components/record-list/kpi-band";
import { PeopleLoadError } from "@/features/people/components/people-load-error";
import { overviewContext } from "@/features/sales/components/overview-support";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

/** The figures above the leave list: requests by state across the organization. */
// skeleton: the page's Suspense fallback is KpiBandSkeleton
export async function LeaveKpis() {
  const [t, permissions, context] = await Promise.all([
    getExtracted("people"),
    getPermissions(),
    overviewContext(),
  ]);

  if (!can(permissions, "leave.request") && !can(permissions, "leave.read")) {
    forbidden();
  }

  if (context === null) {
    return null;
  }

  const { db, tenant } = context;
  const scope = can(permissions, "leave.read") ? { everyone: ["true"] } : {};

  const counts = await Promise.all(
    ["pending", "approved", "rejected"].map((status) =>
      db.leave.requestCount({
        organizationId: tenant,
        filters: { ...scope, status: [status] },
      }),
    ),
  );

  if (counts.some((count) => !count.ok)) {
    return <PeopleLoadError title={t("Leave didn't load")} />;
  }

  const [pending, approved, rejected] = counts.map((count) =>
    count.ok ? String(count.data.value) : "0",
  );

  return (
    <KpiBand
      kpis={[
        {
          label: t("Pending"),
          hint: t("Waiting for approval"),
          value: pending ?? "0",
          icon: <CalendarClockIcon className="size-4" />,
        },
        {
          label: t("Approved"),
          value: approved ?? "0",
          icon: <CalendarCheckIcon className="size-4" />,
        },
        {
          label: t("Rejected"),
          value: rejected ?? "0",
          icon: <CalendarOffIcon className="size-4" />,
        },
      ]}
    />
  );
}
