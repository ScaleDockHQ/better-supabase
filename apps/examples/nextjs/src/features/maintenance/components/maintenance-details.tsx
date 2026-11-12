import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordDetailTabs } from "@/components/record-detail/record-detail-tabs";
import { Badge } from "@/components/reui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { settle } from "@/features/crm/crm-queries";
import { ActionButton } from "@/features/sales/components/action-button";
import {
  DetailTable,
  FactGrid,
} from "@/features/sales/components/detail-table";
import {
  dateFormatter,
  holds,
  requirePermission,
} from "@/features/sales/components/overview-support";
import { Link } from "@/i18n/navigation";
import { trimmed } from "@/lib/form-input";

import {
  changePlanPriority,
  deletePlan,
  generateWorkOrders,
  setPlanStatus,
} from "../maintenance-actions";
import { loadMeters, loadPlan, loadPlans } from "../maintenance-queries";
import {
  planKindLabels,
  planStateLabels,
  priorityLabels,
  RecordReadingDialog,
} from "./maintenance-overviews";

export function MaintenanceDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

const STATE_TONE = new Map<
  string,
  "warning-light" | "info-light" | "secondary" | "outline"
>([
  ["due", "warning-light"],
  ["work_order", "info-light"],
  ["scheduled", "secondary"],
  ["paused", "outline"],
]);

/** A plan with its trigger, its parts and the work order it opened. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function PlanDetail({ id, tab }: { id: string; tab: string }) {
  await requirePermission("maintenance.read");

  const [
    t,
    loaded,
    metersLoaded,
    fmtDate,
    states,
    kinds,
    priorities,
    canManage,
  ] = await Promise.all([
    getExtracted("maintenance"),
    settle(() => loadPlan(id)),
    settle(loadMeters),
    dateFormatter(),
    planStateLabels(),
    planKindLabels(),
    priorityLabels(),
    holds("maintenance.manage"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The plan didn't load")} />;
  }

  const plan = loaded.data;

  if (!plan) {
    notFound();
  }

  const meter =
    metersLoaded.kind === "ok"
      ? metersLoaded.data.find((row) => row.id === plan.meterId)
      : undefined;

  const trigger =
    plan.kind === "time"
      ? t("Every {days} days", { days: String(plan.everyDays ?? 0) })
      : plan.kind === "meter"
        ? t("Every {value} {unit}", {
            value: trimmed(plan.everyValue),
            unit: meter?.unit ?? "",
          })
        : (plan.rrule ?? "–");

  return (
    <RecordDetailFrame
      title={plan.title}
      description={kinds[plan.kind]}
      status={
        <Badge variant={STATE_TONE.get(plan.state) ?? "secondary"}>
          {states[plan.state]}
        </Badge>
      }
      actions={
        canManage ? (
          <>
            {plan.state === "due" ? (
              <ActionButton
                action={generateWorkOrders}
                input={{}}
                label={t("Open work orders")}
                successMessage={t("Work orders opened")}
                variant="default"
              />
            ) : null}
            <ActionButton
              action={setPlanStatus}
              input={{
                planId: plan.id,
                status: plan.state === "paused" ? "active" : "paused",
              }}
              label={plan.state === "paused" ? t("Resume") : t("Pause")}
              successMessage={t("Plan updated")}
            />
            <ActionButton
              action={deletePlan}
              input={{ planId: plan.id }}
              label={t("Delete")}
              successMessage={t("Plan deleted")}
              variant="destructive"
              redirectTo="/maintenance"
            />
          </>
        ) : undefined
      }
    >
      <RecordDetailTabs
        base={`/maintenance/${id}`}
        active={tab}
        tabs={[
          { value: "overview", label: t("Overview") },
          { value: "parts", label: t("Parts") },
          { value: "work-order", label: t("Work order") },
        ]}
      />
      {tab === "parts" ? (
        <DetailTable
          title={t("Parts")}
          description={t(
            "The work order opens with these parts on its pick list.",
          )}
          head={[t("Part"), t("Quantity")]}
          rows={plan.parts.map((part) => ({
            key: part.id,
            cells: [part.name, trimmed(part.quantity)],
          }))}
          emptyTitle={t("No parts")}
          emptyDescription={t("This plan needs no parts.")}
        />
      ) : tab === "work-order" ? (
        <DetailTable
          title={t("Work order")}
          description={t(
            "A due plan opens one dispatch work order. When it is done, the plan's next due date moves ahead.",
          )}
          head={[t("Work order"), t("Status")]}
          rows={
            plan.workOrderId === null
              ? []
              : [
                  {
                    key: plan.workOrderId,
                    cells: [
                      <Link
                        key="link"
                        href="/field/dispatch"
                        className="font-medium hover:underline"
                      >
                        {plan.workOrderId.slice(0, 8)}
                      </Link>,
                      <Badge key="status" variant="info-light">
                        {t("Open")}
                      </Badge>,
                    ],
                  },
                ]
          }
          emptyTitle={t("No open work order")}
          emptyDescription={
            plan.state === "due"
              ? t("The plan is due: open its work order.")
              : t("The plan opens one when it falls due.")
          }
        />
      ) : (
        <>
          <FactGrid
            facts={[
              { label: t("Trigger"), value: trigger },
              { label: t("Next due"), value: fmtDate(plan.nextDueAt) },
              { label: t("Last done"), value: fmtDate(plan.lastDoneAt) },
              { label: t("Priority"), value: priorities[plan.priority] ?? "" },
              {
                label: t("Meter"),
                value: meter
                  ? `${meter.name}: ${trimmed(meter.reading)} ${meter.unit}`
                  : "–",
              },
              { label: t("Parts"), value: String(plan.parts.length) },
            ]}
          />
          {canManage ? (
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-sm text-muted-foreground">
                {t("Priority")}
              </span>
              {(["low", "normal", "high", "urgent"] as const)
                .filter((priority) => priority !== plan.priority)
                .map((priority) => (
                  <ActionButton
                    key={priority}
                    action={changePlanPriority}
                    input={{ planId: plan.id, priority }}
                    label={priorities[priority] ?? priority}
                    successMessage={t("Plan updated")}
                  />
                ))}
            </div>
          ) : null}
        </>
      )}
    </RecordDetailFrame>
  );
}

/**
 * A meter with its reading, the plans that fall due on it and a form for the
 * next reading.
 */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function MeterDetail({ id }: { id: string }) {
  await requirePermission("maintenance.read");

  const [t, metersLoaded, plansLoaded, fmtDate, canRecord, kinds] =
    await Promise.all([
      getExtracted("maintenance"),
      settle(loadMeters),
      settle(loadPlans),
      dateFormatter(),
      holds("maintenance.record"),
      planKindLabels(),
    ]);

  if (metersLoaded.kind === "no-organization") {
    return null;
  }

  if (metersLoaded.kind === "error" || plansLoaded.kind === "error") {
    return <CrmLoadError title={t("The meter didn't load")} />;
  }

  const meter = metersLoaded.data.find((row) => row.id === id);

  if (!meter) {
    notFound();
  }

  const plans =
    plansLoaded.kind === "ok"
      ? plansLoaded.data.filter((plan) => plan.meterId === id)
      : [];

  return (
    <RecordDetailFrame
      title={meter.name}
      description={t("Counts in {unit}", { unit: meter.unit })}
      actions={
        canRecord ? <RecordReadingDialog meterId={meter.id} /> : undefined
      }
    >
      <FactGrid
        facts={[
          {
            label: t("Reading"),
            value: `${trimmed(meter.reading)} ${meter.unit}`,
          },
          { label: t("Read on"), value: fmtDate(meter.readAt) },
          { label: t("Plans on this meter"), value: String(plans.length) },
        ]}
      />
      <DetailTable
        title={t("Plans on this meter")}
        head={[t("Plan"), t("Trigger"), t("Next due")]}
        rows={plans.map((plan) => ({
          key: plan.id,
          cells: [
            <Link
              key="link"
              href={`/maintenance/${plan.id}`}
              className="font-medium hover:underline"
            >
              {plan.title}
            </Link>,
            kinds[plan.kind] ?? plan.kind,
            fmtDate(plan.nextDueAt),
          ],
        }))}
        emptyTitle={t("No plan uses this meter")}
        emptyDescription={t(
          "A meter plan falls due after a number of units on this meter.",
        )}
      />
    </RecordDetailFrame>
  );
}
