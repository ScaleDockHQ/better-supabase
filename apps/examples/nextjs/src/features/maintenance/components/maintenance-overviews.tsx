import { CalendarClockIcon, GaugeIcon, WrenchIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { BlockListQuery } from "@/lib/array-list";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { settle } from "@/features/crm/crm-queries";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import { BlockOverview } from "@/features/sales/components/block-overview";
import {
  dateFormatter,
  holds,
  requirePermission,
} from "@/features/sales/components/overview-support";
import { trimmed } from "@/lib/form-input";

import {
  createMeter,
  createPlan,
  recordCalibration,
  recordReading,
} from "../maintenance-actions";
import {
  loadCalibrations,
  loadMeters,
  loadPlans,
} from "../maintenance-queries";

export function MaintenanceListSkeleton() {
  return <RecordListSkeleton rows={5} />;
}

export async function planStateLabels(): Promise<Record<string, string>> {
  const t = await getExtracted("maintenance");

  return {
    paused: t("Paused"),
    work_order: t("Work order open"),
    due: t("Due"),
    scheduled: t("Scheduled"),
  };
}

export async function planKindLabels(): Promise<Record<string, string>> {
  const t = await getExtracted("maintenance");

  return { time: t("Time"), meter: t("Meter"), rrule: t("Calendar") };
}

export async function priorityLabels(): Promise<Record<string, string>> {
  const t = await getExtracted("maintenance");

  return {
    low: t("Low"),
    normal: t("Normal"),
    high: t("High"),
    urgent: t("Urgent"),
  };
}

const PRIORITY_RANK = new Map([
  ["urgent", 0],
  ["high", 1],
  ["normal", 2],
  ["low", 3],
]);

/** The plans, searched, filtered by state, sorted and paged on the server. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function PlanOverview({ query }: { query: BlockListQuery }) {
  await requirePermission("maintenance.read");

  const [t, loaded, fmtDate, states, kinds, priorities] = await Promise.all([
    getExtracted("maintenance"),
    settle(loadPlans),
    dateFormatter(),
    planStateLabels(),
    planKindLabels(),
    priorityLabels(),
  ]);

  return (
    <BlockOverview
      loaded={loaded}
      query={query}
      spec={{
        search: (plan) => plan.title,
        facet: (plan) => plan.state,
        defaultSort: "due",
        sorts: {
          due: (a, b) =>
            (a.nextDueAt ?? "9999").localeCompare(b.nextDueAt ?? "9999"),
          priority: (a, b) =>
            (PRIORITY_RANK.get(a.priority) ?? 9) -
            (PRIORITY_RANK.get(b.priority) ?? 9),
          title: (a, b) => a.title.localeCompare(b.title),
        },
      }}
      toRow={(plan) => ({
        id: plan.id,
        title: plan.title,
        kind: plan.kind,
        priority: plan.priority,
        state: plan.state,
        nextDueAt: fmtDate(plan.nextDueAt),
        lastDoneAt: fmtDate(plan.lastDoneAt),
      })}
      columns={[
        {
          key: "title",
          header: t("Plan"),
          kind: "link",
          href: "/maintenance/{id}",
          size: 280,
        },
        {
          key: "kind",
          header: t("Trigger"),
          kind: "badge",
          size: 110,
          labels: kinds,
        },
        {
          key: "priority",
          header: t("Priority"),
          kind: "badge",
          size: 110,
          labels: priorities,
          tones: { urgent: "destructive-light", high: "warning-light" },
        },
        { key: "nextDueAt", header: t("Next due"), kind: "muted", size: 130 },
        { key: "lastDoneAt", header: t("Last done"), kind: "muted", size: 130 },
        {
          key: "state",
          header: t("Status"),
          kind: "badge",
          size: 150,
          labels: states,
          tones: {
            due: "warning-light",
            work_order: "info-light",
            scheduled: "secondary",
          },
        },
      ]}
      facet={{ key: "state", label: t("Status"), values: states }}
      sorts={[
        { value: "due", label: t("Soonest due") },
        { value: "priority", label: t("Priority") },
        { value: "title", label: t("Title") },
      ]}
      searchLabel={t("Search plans")}
      errorTitle={t("The plans didn't load")}
      emptyIcon={<WrenchIcon />}
      emptyTitle={t("No plans found")}
      emptyDescription={t(
        "Add a plan that falls due by time, by meter or on a calendar rule, or change the filters.",
      )}
    />
  );
}

/** Every meter with its latest reading; a row opens the meter. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function MeterOverview({ query }: { query: BlockListQuery }) {
  await requirePermission("maintenance.read");

  const [t, loaded, fmtDate, canManage] = await Promise.all([
    getExtracted("maintenance"),
    settle(loadMeters),
    dateFormatter(),
    holds("maintenance.manage"),
  ]);

  return (
    <BlockOverview
      loaded={loaded}
      query={query}
      spec={{
        search: (meter) => `${meter.name} ${meter.unit}`,
        defaultSort: "name",
        sorts: {
          name: (a, b) => a.name.localeCompare(b.name),
          reading: (a, b) => Number(b.reading) - Number(a.reading),
        },
      }}
      toRow={(meter) => ({
        id: meter.id,
        name: meter.name,
        reading: `${trimmed(meter.reading)} ${meter.unit}`,
        readAt: fmtDate(meter.readAt),
      })}
      columns={[
        {
          key: "name",
          header: t("Meter"),
          kind: "link",
          href: "/maintenance/meters/{id}",
          size: 260,
        },
        { key: "reading", header: t("Reading"), kind: "number", size: 160 },
        { key: "readAt", header: t("Read on"), kind: "muted", size: 140 },
      ]}
      sorts={[
        { value: "name", label: t("Name") },
        { value: "reading", label: t("Highest reading") },
      ]}
      searchLabel={t("Search meters")}
      errorTitle={t("The meters didn't load")}
      emptyIcon={<GaugeIcon />}
      emptyTitle={t("No meters yet")}
      emptyDescription={t(
        "A meter counts hours, kilometres or cycles. Plans on a meter fall due after a number of units.",
      )}
      emptyAction={canManage ? <CreateMeterDialog /> : undefined}
    />
  );
}

/** The calibrations, the soonest due first, with the overdue ones marked. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function CalibrationOverview({
  query,
}: {
  query: BlockListQuery;
}) {
  await requirePermission("maintenance.read");

  const [t, loaded, fmtDate] = await Promise.all([
    getExtracted("maintenance"),
    settle(loadCalibrations),
    dateFormatter(),
  ]);

  const results = { pass: t("Pass"), fail: t("Fail"), adjusted: t("Adjusted") };

  return (
    <BlockOverview
      loaded={loaded}
      query={query}
      spec={{
        search: (row) => `${row.instrument} ${row.reference ?? ""}`,
        facet: (row) => row.result,
        defaultSort: "due",
        sorts: {
          due: (a, b) => a.dueAt.localeCompare(b.dueAt),
          done: (a, b) => b.performedAt.localeCompare(a.performedAt),
          instrument: (a, b) => a.instrument.localeCompare(b.instrument),
        },
      }}
      toRow={(row) => ({
        id: row.id,
        instrument: row.instrument,
        result: row.result,
        performedAt: fmtDate(row.performedAt),
        dueAt: fmtDate(row.dueAt),
        reference: row.reference,
        state: row.overdue ? "overdue" : "current",
      })}
      columns={[
        { key: "instrument", header: t("Instrument"), kind: "text", size: 240 },
        {
          key: "result",
          header: t("Result"),
          kind: "badge",
          size: 110,
          labels: results,
          tones: { pass: "success-light", fail: "destructive-light" },
        },
        { key: "performedAt", header: t("Done"), kind: "muted", size: 130 },
        { key: "dueAt", header: t("Next due"), kind: "muted", size: 130 },
        {
          key: "state",
          header: t("Status"),
          kind: "badge",
          size: 110,
          labels: { overdue: t("Overdue"), current: t("Current") },
          tones: { overdue: "destructive-light", current: "success-light" },
        },
        { key: "reference", header: t("Reference"), kind: "muted", size: 160 },
      ]}
      facet={{ key: "result", label: t("Result"), values: results }}
      sorts={[
        { value: "due", label: t("Soonest due") },
        { value: "done", label: t("Latest first") },
        { value: "instrument", label: t("Instrument") },
      ]}
      searchLabel={t("Search calibrations")}
      errorTitle={t("The calibrations didn't load")}
      emptyIcon={<CalendarClockIcon />}
      emptyTitle={t("No calibrations recorded")}
      emptyDescription={t(
        "Record a calibration with the date of the next one, or change the filters.",
      )}
    />
  );
}

// skeleton: the page's Suspense fallback is the skeleton of this view
export async function CreatePlanDialog() {
  const [t, loaded] = await Promise.all([
    getExtracted("maintenance"),
    settle(loadMeters),
  ]);

  const meters = loaded.kind === "ok" ? loaded.data : [];

  return (
    <ActionDialog
      action={createPlan}
      title={t("New plan")}
      description={t(
        "A time plan repeats every number of days, a meter plan after a number of meter units, and a calendar plan follows a recurrence rule.",
      )}
      trigger={t("New plan")}
      submitLabel={t("Create plan")}
      successMessage={t("Plan created")}
      redirectTo="/maintenance/{id}"
      fields={[
        { name: "title", label: t("Title"), kind: "text", required: true },
        {
          name: "kind",
          label: t("Trigger"),
          kind: "select",
          options: [
            { value: "time", label: t("Time") },
            { value: "meter", label: t("Meter") },
            { value: "rrule", label: t("Calendar") },
          ],
        },
        {
          name: "priority",
          label: t("Priority"),
          kind: "select",
          defaultValue: "normal",
          options: [
            { value: "low", label: t("Low") },
            { value: "normal", label: t("Normal") },
            { value: "high", label: t("High") },
            { value: "urgent", label: t("Urgent") },
          ],
        },
        {
          name: "everyDays",
          label: t("Every (days), for a time plan"),
          kind: "number",
          defaultValue: "30",
        },
        ...(meters.length > 0
          ? [
              {
                name: "meterId",
                label: t("Meter, for a meter plan"),
                kind: "select" as const,
                options: meters.map((meter) => ({
                  value: meter.id,
                  label: `${meter.name} (${meter.unit})`,
                })),
              },
              {
                name: "everyValue",
                label: t("Every (units), for a meter plan"),
                kind: "decimal" as const,
              },
            ]
          : []),
        {
          name: "rrule",
          label: t("Recurrence rule, for a calendar plan"),
          kind: "text",
          placeholder: "FREQ=MONTHLY;BYMONTHDAY=1",
        },
        {
          name: "startsOn",
          label: t("First date, for a calendar plan"),
          kind: "date",
        },
      ]}
    />
  );
}

// skeleton: renders from props and translations, so nothing of its own suspends
export async function CreateMeterDialog() {
  const t = await getExtracted("maintenance");

  return (
    <ActionDialog
      action={createMeter}
      title={t("New meter")}
      trigger={t("New meter")}
      submitLabel={t("Create meter")}
      successMessage={t("Meter created")}
      variant="outline"
      fields={[
        { name: "name", label: t("Name"), kind: "text", required: true },
        {
          name: "unit",
          label: t("Unit"),
          kind: "text",
          required: true,
          placeholder: "h",
        },
      ]}
    />
  );
}

// skeleton: renders from props and translations, so nothing of its own suspends
export async function RecordReadingDialog({ meterId }: { meterId: string }) {
  const t = await getExtracted("maintenance");

  return (
    <ActionDialog
      action={recordReading}
      title={t("Record a reading")}
      description={t("A reading never goes below the previous one.")}
      trigger={t("Record reading")}
      submitLabel={t("Record")}
      successMessage={t("Reading recorded")}
      variant="outline"
      hidden={{ meterId }}
      fields={[
        { name: "value", label: t("Reading"), kind: "decimal", required: true },
      ]}
    />
  );
}

// skeleton: renders from props and translations, so nothing of its own suspends
export async function RecordCalibrationDialog() {
  const t = await getExtracted("maintenance");

  return (
    <ActionDialog
      action={recordCalibration}
      title={t("Record a calibration")}
      description={t("The date defaults to today.")}
      trigger={t("Record calibration")}
      submitLabel={t("Record")}
      successMessage={t("Calibration recorded")}
      variant="outline"
      fields={[
        {
          name: "instrument",
          label: t("Instrument"),
          kind: "text",
          required: true,
        },
        { name: "performedOn", label: t("Done on"), kind: "date" },
        {
          name: "everyDays",
          label: t("Next one in (days)"),
          kind: "number",
          defaultValue: "365",
        },
        {
          name: "result",
          label: t("Result"),
          kind: "select",
          options: [
            { value: "pass", label: t("Pass") },
            { value: "fail", label: t("Fail") },
            { value: "adjusted", label: t("Adjusted") },
          ],
        },
        { name: "reference", label: t("Reference"), kind: "text" },
      ]}
    />
  );
}
