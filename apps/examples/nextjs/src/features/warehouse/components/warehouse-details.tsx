import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordDetailTabs } from "@/components/record-detail/record-detail-tabs";
import { Badge } from "@/components/reui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { settle } from "@/features/crm/crm-queries";
import { ActionButton } from "@/features/sales/components/action-button";
import { ActionDialog } from "@/features/sales/components/action-dialog";
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
  completePickList,
  deletePutawayRule,
  optimizePickRoute,
  postCycleCount,
  recordPick,
  runCountPlans,
  transitionWave,
} from "../warehouse-actions";
import {
  loadCountPlans,
  loadLookups,
  loadPickList,
  loadPickLists,
  loadPutawayRules,
  loadVariance,
  loadWaves,
} from "../warehouse-queries";
import { pickStatusLabels, waveStatusLabels } from "./warehouse-overviews";

export function WarehouseDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

async function lookups() {
  const loaded = await settle(loadLookups);
  const data = loaded.kind === "ok" ? loaded.data : undefined;

  return {
    locations: new Map(
      (data?.locations ?? []).map((row) => [row.id, row.name]),
    ),
    bins: new Map((data?.bins ?? []).map((row) => [row.id, row.code])),
    variants: new Map(
      (data?.variants ?? []).map((row) => [row.id, `${row.sku} ${row.title}`]),
    ),
  };
}

/**
 * One pick list: its lines in walking order, a pick form per line, and the
 * route and completion actions.
 */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function PickListDetail({ id, tab }: { id: string; tab: string }) {
  await requirePermission("warehouse.read");

  const [t, loaded, fmtDate, lookup, statuses, canPick, canManage] =
    await Promise.all([
      getExtracted("warehouse"),
      settle(() => loadPickList(id)),
      dateFormatter(),
      lookups(),
      pickStatusLabels(),
      holds("warehouse.pick"),
      holds("warehouse.manage"),
    ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The pick list didn't load")} />;
  }

  const list = loaded.data;

  if (!list) {
    notFound();
  }

  const open = list.status === "open";

  const lineStatus = {
    open: t("Open"),
    picked: t("Picked"),
    short: t("Short"),
    cancelled: t("Cancelled"),
  } satisfies Record<(typeof list.items)[number]["status"], string>;

  return (
    <RecordDetailFrame
      title={`${list.documentType} ${list.documentId.slice(0, 8)}`}
      description={lookup.locations.get(list.locationId)}
      status={
        <Badge variant={open ? "warning-light" : "success-light"}>
          {statuses[list.status]}
        </Badge>
      }
      actions={
        open ? (
          <>
            {canManage ? (
              <ActionButton
                action={optimizePickRoute}
                input={{ pickListId: list.id }}
                label={t("Optimize route")}
                successMessage={t("Route saved")}
              />
            ) : null}
            {canPick ? (
              <ActionButton
                action={completePickList}
                input={{ pickListId: list.id }}
                label={t("Complete list")}
                successMessage={t("Pick list completed")}
                variant="default"
              />
            ) : null}
          </>
        ) : undefined
      }
    >
      <RecordDetailTabs
        base={`/warehouse/${id}`}
        active={tab}
        tabs={[
          { value: "lines", label: t("Lines") },
          { value: "details", label: t("Details") },
        ]}
      />
      {tab === "details" ? (
        <FactGrid
          facts={[
            { label: t("Document"), value: list.documentType },
            { label: t("Document id"), value: list.documentId },
            { label: t("Created"), value: fmtDate(list.createdAt) },
            { label: t("Picked on"), value: fmtDate(list.pickedAt) },
            {
              label: t("Lines picked"),
              value: `${list.picked} / ${list.lines}`,
            },
            {
              label: t("Wave"),
              value: list.waveId ? list.waveId.slice(0, 8) : "–",
            },
          ]}
        />
      ) : (
        <DetailTable
          title={t("Lines")}
          description={t(
            "Lines follow the walking route. Record what the picker found; the stock moves when the document ships.",
          )}
          head={[
            t("Route"),
            t("Variant"),
            t("Bin"),
            t("Asked"),
            t("Picked"),
            t("Status"),
            "",
          ]}
          rows={list.items.map((line) => ({
            key: line.id,
            cells: [
              line.route === null ? "–" : String(line.route),
              lookup.variants.get(line.variantId) ?? line.variantId.slice(0, 8),
              lookup.bins.get(line.binId ?? "") ?? "–",
              trimmed(line.quantity),
              trimmed(line.picked),
              <Badge
                key="status"
                variant={
                  line.status === "picked"
                    ? "success-light"
                    : line.status === "short"
                      ? "warning-light"
                      : "secondary"
                }
              >
                {lineStatus[line.status]}
              </Badge>,
              open && canPick && line.status === "open" ? (
                <ActionDialog
                  key="pick"
                  action={recordPick}
                  title={t("Record a pick")}
                  trigger={t("Record pick")}
                  submitLabel={t("Record")}
                  successMessage={t("Pick recorded")}
                  variant="outline"
                  hidden={{ lineId: line.id }}
                  fields={[
                    {
                      name: "quantity",
                      label: t("Quantity found"),
                      kind: "decimal",
                      required: true,
                      defaultValue: trimmed(line.quantity),
                    },
                  ]}
                />
              ) : null,
            ],
          }))}
          emptyTitle={t("No lines")}
          emptyDescription={t("The document had no open allocations.")}
        />
      )}
    </RecordDetailFrame>
  );
}

/** A wave with the pick lists released with it. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function WaveDetail({ id }: { id: string }) {
  await requirePermission("warehouse.read");

  const [t, waves, lists, fmtDate, lookup, statuses, listStatuses, canManage] =
    await Promise.all([
      getExtracted("warehouse"),
      settle(loadWaves),
      settle(loadPickLists),
      dateFormatter(),
      lookups(),
      waveStatusLabels(),
      pickStatusLabels(),
      holds("warehouse.manage"),
    ]);

  if (waves.kind === "no-organization") {
    return null;
  }

  if (waves.kind === "error" || lists.kind === "error") {
    return <CrmLoadError title={t("The wave didn't load")} />;
  }

  const wave = waves.data.find((row) => row.id === id);

  if (!wave) {
    notFound();
  }

  const inWave =
    lists.kind === "ok" ? lists.data.filter((row) => row.waveId === id) : [];

  return (
    <RecordDetailFrame
      title={wave.name}
      description={lookup.locations.get(wave.locationId)}
      status={
        <Badge
          variant={
            wave.status === "released"
              ? "info-light"
              : wave.status === "completed"
                ? "success-light"
                : "secondary"
          }
        >
          {statuses[wave.status]}
        </Badge>
      }
      actions={
        canManage && (wave.status === "draft" || wave.status === "released") ? (
          <>
            {wave.status === "draft" ? (
              <ActionButton
                action={transitionWave}
                input={{ waveId: wave.id, action: "release" }}
                label={t("Release")}
                successMessage={t("Wave released")}
                variant="default"
              />
            ) : null}
            <ActionButton
              action={transitionWave}
              input={{ waveId: wave.id, action: "cancel" }}
              label={t("Cancel wave")}
              successMessage={t("Wave cancelled")}
              variant="destructive"
            />
          </>
        ) : undefined
      }
    >
      <FactGrid
        facts={[
          { label: t("Created"), value: fmtDate(wave.createdAt) },
          { label: t("Pick lists"), value: String(wave.lists) },
          { label: t("Still open"), value: String(wave.openLists) },
        ]}
      />
      <DetailTable
        title={t("Pick lists in this wave")}
        head={[t("Document"), t("Status"), t("Lines picked")]}
        rows={inWave.map((row) => ({
          key: row.id,
          cells: [
            <Link
              key="link"
              href={`/warehouse/${row.id}`}
              className="font-medium hover:underline"
            >
              {row.documentType} {row.documentId.slice(0, 8)}
            </Link>,
            listStatuses[row.status] ?? row.status,
            `${row.picked} / ${row.lines}`,
          ],
        }))}
        emptyTitle={t("No pick lists yet")}
        emptyDescription={t(
          "Create a pick list for a document and add it to this wave.",
        )}
      />
    </RecordDetailFrame>
  );
}

/** A putaway rule, with a delete. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function RuleDetail({ id }: { id: string }) {
  await requirePermission("warehouse.read");

  const [t, loaded, lookup, canManage] = await Promise.all([
    getExtracted("warehouse"),
    settle(loadPutawayRules),
    lookups(),
    holds("warehouse.manage"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The rule didn't load")} />;
  }

  const rule = loaded.data.find((row) => row.id === id);

  if (!rule) {
    notFound();
  }

  return (
    <RecordDetailFrame
      title={t("Rule for bin {bin}", {
        bin: lookup.bins.get(rule.binId) ?? rule.binId.slice(0, 8),
      })}
      description={lookup.locations.get(rule.locationId)}
      status={
        <Badge variant={rule.active ? "success-light" : "secondary"}>
          {rule.active ? t("Active") : t("Inactive")}
        </Badge>
      }
      actions={
        canManage ? (
          <ActionButton
            action={deletePutawayRule}
            input={{ ruleId: rule.id }}
            label={t("Delete")}
            successMessage={t("Rule deleted")}
            variant="destructive"
            redirectTo="/warehouse?tab=putaway"
          />
        ) : undefined
      }
    >
      <FactGrid
        facts={[
          {
            label: t("Variant"),
            value: rule.variantId
              ? (lookup.variants.get(rule.variantId) ?? "–")
              : t("Any variant"),
          },
          { label: t("Priority"), value: String(rule.priority) },
          { label: t("Max quantity"), value: trimmed(rule.maxQuantity) },
        ]}
      />
    </RecordDetailFrame>
  );
}

/** A cycle count plan with the variance of its last count and the post action. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function CountPlanDetail({ id }: { id: string }) {
  await requirePermission("warehouse.read");

  const [t, loaded, fmtDate, lookup, canManage] = await Promise.all([
    getExtracted("warehouse"),
    settle(loadCountPlans),
    dateFormatter(),
    lookups(),
    holds("warehouse.manage"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The count plan didn't load")} />;
  }

  const plan = loaded.data.find((row) => row.id === id);

  if (!plan) {
    notFound();
  }

  const variance = plan.lastCountId
    ? await settle(() => loadVariance(plan.lastCountId ?? ""))
    : undefined;

  const checked = variance?.kind === "ok" ? variance.data : undefined;

  return (
    <RecordDetailFrame
      title={plan.name}
      description={lookup.locations.get(plan.locationId)}
      status={
        <Badge variant={plan.due ? "warning-light" : "secondary"}>
          {plan.due ? t("Due") : t("Scheduled")}
        </Badge>
      }
      actions={
        canManage ? (
          <>
            <ActionButton
              action={runCountPlans}
              input={{ planId: plan.id }}
              label={t("Open count now")}
              successMessage={t("Count opened")}
            />
            {checked ? (
              <ActionButton
                action={postCycleCount}
                input={{ countId: checked.countId, approve: checked.overLimit }}
                label={
                  checked.overLimit ? t("Approve and post") : t("Post count")
                }
                successMessage={t("Count posted")}
                variant="default"
              />
            ) : null}
          </>
        ) : undefined
      }
    >
      <FactGrid
        facts={[
          { label: t("Every (days)"), value: String(plan.everyDays) },
          { label: t("Variance limit"), value: `${plan.varianceLimitPct}%` },
          { label: t("Next run"), value: fmtDate(plan.nextRunOn) },
          { label: t("Last run"), value: fmtDate(plan.lastRunAt) },
        ]}
      />
      <DetailTable
        title={t("Variance of the last count")}
        description={
          checked
            ? t("The largest variance is {max}% against a limit of {limit}%.", {
                max: checked.maxVariancePct,
                limit: checked.limitPct,
              })
            : t("Open a count to see its variance.")
        }
        head={[
          t("Variant"),
          t("Expected"),
          t("Counted"),
          t("Variance"),
          t("Percent"),
        ]}
        rows={(checked?.lines ?? []).map((line) => ({
          key: line.lineId,
          cells: [
            lookup.variants.get(line.variantId) ?? line.variantId.slice(0, 8),
            trimmed(line.expected),
            trimmed(line.counted),
            trimmed(line.variance),
            `${line.variancePct}%`,
          ],
        }))}
        emptyTitle={checked ? t("No lines counted yet") : t("No count yet")}
        emptyDescription={t(
          "Run the plan to open a stock count, record the counted quantities in inventory, then post it here.",
        )}
      />
    </RecordDetailFrame>
  );
}
