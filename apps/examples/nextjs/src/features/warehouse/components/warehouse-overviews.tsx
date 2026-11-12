import {
  ClipboardCheckIcon,
  ClipboardListIcon,
  LayersIcon,
  MapPinnedIcon,
} from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { BlockListQuery } from "@/lib/array-list";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { settle } from "@/features/crm/crm-queries";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import { BlockOverview } from "@/features/sales/components/block-overview";
import { DetailTable } from "@/features/sales/components/detail-table";
import {
  dateFormatter,
  requirePermission,
} from "@/features/sales/components/overview-support";
import { trimmed } from "@/lib/form-input";

import type { CountPlanRow } from "../warehouse-queries";

import {
  createCountPlan,
  createPickWave,
  savePutawayRule,
} from "../warehouse-actions";
import {
  loadCountPlans,
  loadLookups,
  loadPickLists,
  loadPutawayRules,
  loadSlotting,
  loadWaves,
} from "../warehouse-queries";

function countState(plan: CountPlanRow): "inactive" | "due" | "scheduled" {
  if (plan.active) {
    return plan.due ? "due" : "scheduled";
  }

  return "inactive";
}

export function WarehouseListSkeleton() {
  return <RecordListSkeleton rows={5} />;
}

async function names() {
  const lookups = await settle(loadLookups);
  const data = lookups.kind === "ok" ? lookups.data : undefined;

  return {
    locations: new Map(
      (data?.locations ?? []).map((row) => [row.id, row.name]),
    ),
    bins: new Map((data?.bins ?? []).map((row) => [row.id, row.code])),
    variants: new Map(
      (data?.variants ?? []).map((row) => [row.id, `${row.sku} ${row.title}`]),
    ),
    options: data,
  };
}

export async function pickStatusLabels(): Promise<Record<string, string>> {
  const t = await getExtracted("warehouse");

  return { open: t("Open"), picked: t("Picked"), cancelled: t("Cancelled") };
}

export async function waveStatusLabels(): Promise<Record<string, string>> {
  const t = await getExtracted("warehouse");

  return {
    draft: t("Draft"),
    released: t("Released"),
    completed: t("Completed"),
    cancelled: t("Cancelled"),
  };
}

/**
 * Pick lists by document, searched, filtered by status, sorted and paged on the
 * server.
 */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function PickOverview({ query }: { query: BlockListQuery }) {
  await requirePermission("warehouse.read");

  const [t, loaded, fmtDate, lookup, statuses] = await Promise.all([
    getExtracted("warehouse"),
    settle(loadPickLists),
    dateFormatter(),
    names(),
    pickStatusLabels(),
  ]);

  return (
    <BlockOverview
      loaded={loaded}
      query={query}
      spec={{
        search: (list) => `${list.documentType} ${list.documentId}`,
        facet: (list) => list.status,
        defaultSort: "newest",
        sorts: {
          newest: (a, b) => b.createdAt.localeCompare(a.createdAt),
          oldest: (a, b) => a.createdAt.localeCompare(b.createdAt),
          progress: (a, b) =>
            a.picked / Math.max(a.lines, 1) - b.picked / Math.max(b.lines, 1),
        },
      }}
      toRow={(list) => ({
        id: list.id,
        document: `${list.documentType} ${list.documentId.slice(0, 8)}`,
        location: lookup.locations.get(list.locationId) ?? "–",
        status: list.status,
        progress: `${list.picked} / ${list.lines}`,
        createdAt: fmtDate(list.createdAt),
      })}
      columns={[
        {
          key: "document",
          header: t("Document"),
          kind: "link",
          href: "/warehouse/{id}",
          size: 240,
        },
        { key: "location", header: t("Location"), kind: "text", size: 160 },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 120,
          labels: statuses,
          tones: { open: "warning-light", picked: "success-light" },
        },
        {
          key: "progress",
          header: t("Lines picked"),
          kind: "number",
          size: 130,
        },
        { key: "createdAt", header: t("Created"), kind: "muted", size: 130 },
      ]}
      facet={{ key: "status", label: t("Status"), values: statuses }}
      sorts={[
        { value: "newest", label: t("Newest first") },
        { value: "oldest", label: t("Oldest first") },
        { value: "progress", label: t("Least picked") },
      ]}
      searchLabel={t("Search pick lists")}
      errorTitle={t("The pick lists didn't load")}
      emptyIcon={<ClipboardListIcon />}
      emptyTitle={t("No pick lists found")}
      emptyDescription={t(
        "A pick list is made from a document's open stock allocations, or change the filters.",
      )}
    />
  );
}

/** Pick waves group pick lists; a row opens the wave. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function WaveOverview({ query }: { query: BlockListQuery }) {
  await requirePermission("warehouse.read");

  const [t, loaded, fmtDate, lookup, statuses] = await Promise.all([
    getExtracted("warehouse"),
    settle(loadWaves),
    dateFormatter(),
    names(),
    waveStatusLabels(),
  ]);

  return (
    <BlockOverview
      loaded={loaded}
      query={query}
      spec={{
        search: (wave) => wave.name,
        facet: (wave) => wave.status,
        defaultSort: "newest",
        sorts: {
          newest: (a, b) => b.createdAt.localeCompare(a.createdAt),
          name: (a, b) => a.name.localeCompare(b.name),
          open: (a, b) => b.openLists - a.openLists,
        },
      }}
      toRow={(wave) => ({
        id: wave.id,
        name: wave.name,
        location: lookup.locations.get(wave.locationId) ?? "–",
        status: wave.status,
        lists: `${wave.lists - wave.openLists} / ${wave.lists}`,
        createdAt: fmtDate(wave.createdAt),
      })}
      columns={[
        {
          key: "name",
          header: t("Wave"),
          kind: "link",
          href: "/warehouse/waves/{id}",
          size: 240,
        },
        { key: "location", header: t("Location"), kind: "text", size: 160 },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 120,
          labels: statuses,
          tones: { released: "info-light", completed: "success-light" },
        },
        { key: "lists", header: t("Lists done"), kind: "number", size: 120 },
        { key: "createdAt", header: t("Created"), kind: "muted", size: 130 },
      ]}
      facet={{ key: "status", label: t("Status"), values: statuses }}
      sorts={[
        { value: "newest", label: t("Newest first") },
        { value: "name", label: t("Name") },
        { value: "open", label: t("Most open lists") },
      ]}
      searchLabel={t("Search waves")}
      errorTitle={t("The waves didn't load")}
      emptyIcon={<LayersIcon />}
      emptyTitle={t("No waves found")}
      emptyDescription={t(
        "A wave releases several pick lists to pickers at once.",
      )}
    />
  );
}

/** The putaway rules, and the slotting suggestions of the first location. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function PutawayOverview({ query }: { query: BlockListQuery }) {
  await requirePermission("warehouse.read");

  const [t, loaded, lookup] = await Promise.all([
    getExtracted("warehouse"),
    settle(loadPutawayRules),
    names(),
  ]);

  const firstLocation = lookup.options?.locations[0];

  const slotting = firstLocation
    ? await settle(() => loadSlotting(firstLocation.id))
    : undefined;

  return (
    <div className="flex flex-col gap-6">
      <BlockOverview
        loaded={loaded}
        query={query}
        spec={{
          search: (rule) =>
            `${lookup.bins.get(rule.binId) ?? ""} ${lookup.variants.get(rule.variantId ?? "") ?? ""}`,
          facet: (rule) => (rule.active ? "active" : "inactive"),
          defaultSort: "priority",
          sorts: {
            priority: (a, b) => a.priority - b.priority,
            bin: (a, b) =>
              (lookup.bins.get(a.binId) ?? "").localeCompare(
                lookup.bins.get(b.binId) ?? "",
              ),
          },
        }}
        toRow={(rule) => ({
          id: rule.id,
          bin: lookup.bins.get(rule.binId) ?? "–",
          location: lookup.locations.get(rule.locationId) ?? "–",
          variant: rule.variantId
            ? (lookup.variants.get(rule.variantId) ?? "–")
            : t("Any variant"),
          priority: rule.priority,
          maxQuantity:
            rule.maxQuantity === null ? null : trimmed(rule.maxQuantity),
          state: rule.active ? "active" : "inactive",
        })}
        columns={[
          {
            key: "bin",
            header: t("Bin"),
            kind: "link",
            href: "/warehouse/rules/{id}",
            size: 140,
          },
          { key: "location", header: t("Location"), kind: "text", size: 160 },
          { key: "variant", header: t("Variant"), kind: "text", size: 240 },
          { key: "priority", header: t("Priority"), kind: "number", size: 100 },
          {
            key: "maxQuantity",
            header: t("Max quantity"),
            kind: "muted",
            size: 130,
          },
          {
            key: "state",
            header: t("Status"),
            kind: "badge",
            size: 110,
            labels: { active: t("Active"), inactive: t("Inactive") },
            tones: { active: "success-light" },
          },
        ]}
        facet={{
          key: "state",
          label: t("Status"),
          values: { active: t("Active"), inactive: t("Inactive") },
        }}
        sorts={[
          { value: "priority", label: t("Priority") },
          { value: "bin", label: t("Bin") },
        ]}
        searchLabel={t("Search putaway rules")}
        errorTitle={t("The putaway rules didn't load")}
        emptyIcon={<MapPinnedIcon />}
        emptyTitle={t("No putaway rules")}
        emptyDescription={t(
          "A rule sends incoming stock of a variant to a bin, the lowest priority number first.",
        )}
      />
      {slotting?.kind === "ok" && firstLocation ? (
        <DetailTable
          title={t("Slotting suggestions for {location}", {
            location: firstLocation.name,
          })}
          description={t(
            "The fastest movers of the last 90 days and the bin that is closest to the dock.",
          )}
          head={[
            t("Variant"),
            t("Picks"),
            t("On hand"),
            t("Current bin"),
            t("Suggested bin"),
          ]}
          rows={slotting.data.map((row) => ({
            key: row.variantId,
            cells: [
              lookup.variants.get(row.variantId) ?? row.variantId.slice(0, 8),
              String(row.picks),
              trimmed(row.onHand),
              lookup.bins.get(row.currentBinId ?? "") ?? "–",
              row.action === "keep"
                ? t("Keep")
                : (lookup.bins.get(row.suggestedBinId ?? "") ?? "–"),
            ],
          }))}
          emptyTitle={t("No picks to slot yet")}
          emptyDescription={t(
            "Suggestions appear once items have been picked.",
          )}
        />
      ) : null}
    </div>
  );
}

/** Cycle count plans with the date of the next run. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function CountOverview({ query }: { query: BlockListQuery }) {
  await requirePermission("warehouse.read");

  const [t, loaded, fmtDate, lookup] = await Promise.all([
    getExtracted("warehouse"),
    settle(loadCountPlans),
    dateFormatter(),
    names(),
  ]);

  const states = {
    due: t("Due"),
    scheduled: t("Scheduled"),
    inactive: t("Inactive"),
  };

  return (
    <BlockOverview
      loaded={loaded}
      query={query}
      spec={{
        search: (plan) => plan.name,
        facet: countState,
        defaultSort: "next",
        sorts: {
          next: (a, b) => a.nextRunOn.localeCompare(b.nextRunOn),
          name: (a, b) => a.name.localeCompare(b.name),
        },
      }}
      toRow={(plan) => ({
        id: plan.id,
        name: plan.name,
        location: lookup.locations.get(plan.locationId) ?? "–",
        everyDays: `${plan.everyDays}`,
        limit: `${plan.varianceLimitPct}%`,
        nextRunOn: fmtDate(plan.nextRunOn),
        state: countState(plan),
      })}
      columns={[
        {
          key: "name",
          header: t("Plan"),
          kind: "link",
          href: "/warehouse/counts/{id}",
          size: 240,
        },
        { key: "location", header: t("Location"), kind: "text", size: 160 },
        {
          key: "everyDays",
          header: t("Every (days)"),
          kind: "number",
          size: 110,
        },
        {
          key: "limit",
          header: t("Variance limit"),
          kind: "number",
          size: 130,
        },
        { key: "nextRunOn", header: t("Next run"), kind: "muted", size: 130 },
        {
          key: "state",
          header: t("Status"),
          kind: "badge",
          size: 120,
          labels: states,
          tones: { due: "warning-light", scheduled: "secondary" },
        },
      ]}
      facet={{ key: "state", label: t("Status"), values: states }}
      sorts={[
        { value: "next", label: t("Next run") },
        { value: "name", label: t("Name") },
      ]}
      searchLabel={t("Search count plans")}
      errorTitle={t("The count plans didn't load")}
      emptyIcon={<ClipboardCheckIcon />}
      emptyTitle={t("No count plans")}
      emptyDescription={t(
        "A plan opens a stock count at a location on a schedule and checks the variance before it posts.",
      )}
    />
  );
}

// skeleton: renders from props and translations, so nothing of its own suspends
export async function CreateWaveDialog() {
  const [t, lookup] = await Promise.all([getExtracted("warehouse"), names()]);

  return (
    <ActionDialog
      action={createPickWave}
      title={t("New wave")}
      trigger={t("New wave")}
      submitLabel={t("Create wave")}
      successMessage={t("Wave created")}
      redirectTo="/warehouse/waves/{id}"
      fields={[
        { name: "name", label: t("Name"), kind: "text", required: true },
        {
          name: "locationId",
          label: t("Location"),
          kind: "select",
          options: (lookup.options?.locations ?? []).map((row) => ({
            value: row.id,
            label: row.name,
          })),
        },
      ]}
    />
  );
}

// skeleton: renders from props and translations, so nothing of its own suspends
export async function CreateRuleDialog() {
  const [t, lookup] = await Promise.all([getExtracted("warehouse"), names()]);
  const options = lookup.options;

  return (
    <ActionDialog
      action={savePutawayRule}
      title={t("New putaway rule")}
      trigger={t("New rule")}
      submitLabel={t("Save rule")}
      successMessage={t("Rule saved")}
      redirectTo="/warehouse/rules/{id}"
      fields={[
        {
          name: "locationId",
          label: t("Location"),
          kind: "select",
          options: (options?.locations ?? []).map((row) => ({
            value: row.id,
            label: row.name,
          })),
        },
        {
          name: "binId",
          label: t("Bin"),
          kind: "select",
          options: (options?.bins ?? []).map((row) => ({
            value: row.id,
            label: row.code,
          })),
        },
        {
          name: "variantId",
          label: t("Variant (optional)"),
          kind: "select",
          options: [
            { value: "", label: t("Any variant") },
            ...(options?.variants ?? []).map((row) => ({
              value: row.id,
              label: `${row.sku} ${row.title}`,
            })),
          ],
        },
        {
          name: "priority",
          label: t("Priority"),
          kind: "number",
          defaultValue: "10",
        },
        { name: "maxQuantity", label: t("Max quantity"), kind: "decimal" },
      ]}
    />
  );
}

// skeleton: renders from props and translations, so nothing of its own suspends
export async function CreateCountPlanDialog() {
  const [t, lookup] = await Promise.all([getExtracted("warehouse"), names()]);

  return (
    <ActionDialog
      action={createCountPlan}
      title={t("New count plan")}
      trigger={t("New count plan")}
      submitLabel={t("Create plan")}
      successMessage={t("Count plan created")}
      redirectTo="/warehouse/counts/{id}"
      fields={[
        { name: "name", label: t("Name"), kind: "text", required: true },
        {
          name: "locationId",
          label: t("Location"),
          kind: "select",
          options: (lookup.options?.locations ?? []).map((row) => ({
            value: row.id,
            label: row.name,
          })),
        },
        {
          name: "everyDays",
          label: t("Every (days)"),
          kind: "number",
          defaultValue: "30",
        },
        {
          name: "varianceLimitPct",
          label: t("Variance limit (percent)"),
          kind: "decimal",
          defaultValue: "5",
        },
      ]}
    />
  );
}
