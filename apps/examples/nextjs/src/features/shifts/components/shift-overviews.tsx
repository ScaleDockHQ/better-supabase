import {
  CalendarDaysIcon,
  CircleCheckIcon,
  UserCheckIcon,
  UserPlusIcon,
} from "lucide-react";
import { getExtracted } from "next-intl/server";
import { io } from "next/cache";
import { Temporal } from "temporal-polyfill";

import { BlockListView } from "@/components/record-list/block-list-view";
import { KpiBand } from "@/components/record-list/kpi-band";
import { PeopleLoadError } from "@/features/people/components/people-load-error";
import { dateFormatter } from "@/features/sales/components/overview-support";

import { getRoster } from "../shifts-queries";

async function thisWeek() {
  await io();
  const today = Temporal.Now.plainDateISO("UTC");

  return today.subtract({ days: today.dayOfWeek - 1 }).toString();
}

/** The figures above the shift views: this week's shifts and their places. */
// skeleton: the page's Suspense fallback is KpiBandSkeleton
export async function ShiftKpis() {
  const [t, state] = await Promise.all([
    getExtracted("shifts"),
    thisWeek().then(getRoster),
  ]);

  if (state.kind === "no-organization") {
    return null;
  }

  if (state.kind === "error") {
    return <PeopleLoadError title={t("The roster didn't load")} />;
  }

  const shifts = state.data;
  const places = shifts.reduce((sum, shift) => sum + shift.headcount, 0);
  const filled = shifts.reduce((sum, shift) => sum + shift.assigned, 0);
  const requested = shifts.reduce((sum, shift) => sum + shift.requested, 0);

  return (
    <KpiBand
      kpis={[
        {
          label: t("Shifts"),
          hint: t("This week"),
          value: String(shifts.length),
          icon: <CalendarDaysIcon className="size-4" />,
        },
        {
          label: t("Places filled"),
          value: `${filled} / ${places}`,
          icon: <UserCheckIcon className="size-4" />,
        },
        {
          label: t("Open places"),
          value: String(Math.max(places - filled, 0)),
          icon: <UserPlusIcon className="size-4" />,
        },
        {
          label: t("Requests"),
          hint: t("Waiting for a planner"),
          value: String(requested),
          icon: <CircleCheckIcon className="size-4" />,
        },
      ]}
    />
  );
}

/** This week's shifts as a table. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function ShiftTable() {
  const [t, state, fmtDate] = await Promise.all([
    getExtracted("shifts"),
    thisWeek().then(getRoster),
    dateFormatter(),
  ]);

  if (state.kind === "no-organization") {
    return null;
  }

  if (state.kind === "error") {
    return <PeopleLoadError title={t("The roster didn't load")} />;
  }

  return (
    <BlockListView
      rows={state.data.map((shift) => ({
        id: shift.id,
        day: fmtDate(shift.startsAt),
        status: shift.status,
        places: `${shift.assigned} / ${shift.headcount}`,
        requested: shift.requested,
      }))}
      columns={[
        {
          key: "day",
          header: t("Day"),
          kind: "link",
          href: "/shifts/{id}",
          size: 200,
        },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 130,
          labels: {
            draft: t("Draft"),
            published: t("Published"),
            canceled: t("Canceled"),
          },
          tones: {
            draft: "secondary",
            published: "success-light",
            canceled: "destructive-light",
          },
        },
        {
          key: "places",
          header: t("Places filled"),
          kind: "number",
          size: 140,
        },
        { key: "requested", header: t("Requests"), kind: "number", size: 120 },
      ]}
      sorts={[]}
      nextCursor={null}
      emptyIcon={<CalendarDaysIcon />}
      emptyTitle={t("No shifts this week")}
      emptyDescription={t("Generate the week's shifts from a template.")}
    />
  );
}
