import { CoinsIcon, StoreIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { settle } from "@/features/crm/crm-queries";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import { BlockOverview } from "@/features/sales/components/block-overview";
import {
  dateFormatter,
  holds,
  moneyFormatter,
  requirePermission,
} from "@/features/sales/components/overview-support";

import { createTill, openSession } from "../tills-actions";
import { loadOpenTillIds, loadTills } from "../tills-queries";

export function TillsListSkeleton() {
  return <RecordListSkeleton rows={5} />;
}

/** Shifts, searched by till, filtered by status, sorted and paged on the server. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function SessionOverview({
  query,
}: {
  query: RecordListUrlQuery;
}) {
  await requirePermission("tills.read");

  const [t, tills, fmtDate, fmtMoney] = await Promise.all([
    getExtracted("tills"),
    settle(loadTills),
    dateFormatter(),
    moneyFormatter(),
  ]);

  const statuses = { open: t("Open"), closed: t("Closed") };

  const tillNames = new Map(
    tills.kind === "ok" ? tills.data.map((till) => [till.id, till.name]) : [],
  );

  return (
    <BlockOverview
      pager={({ db }) => ({
        page: (options) => db.tills.sessionPage(options),
        facets: (options) => db.tills.sessionFacets(options),
      })}
      map={{
        sorts: {
          newest: { by: "openedAt", direction: "desc" },
          oldest: { by: "openedAt" },
        },
        filters: { f: "status" },
        facets: { f: "status" },
      }}
      query={query}
      toRow={(row) => ({
        id: row.id,
        till: tillNames.get(row.tillId) ?? "",
        status: row.status,
        openingFloat: fmtMoney(row.openingFloat),
        expected: fmtMoney(row.expected),
        openedAt: fmtDate(row.openedAt.toString()),
        closedAt: fmtDate(row.closedAt?.toString()),
      })}
      columns={[
        {
          key: "till",
          header: t("Till"),
          kind: "link",
          href: "/tills/{id}",
          size: 220,
        },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 100,
          labels: statuses,
          tones: { open: "info-light", closed: "secondary" },
        },
        { key: "openingFloat", header: t("Float"), kind: "number", size: 120 },
        {
          key: "expected",
          header: t("Expected cash"),
          kind: "number",
          size: 140,
        },
        { key: "openedAt", header: t("Opened"), kind: "muted", size: 130 },
        { key: "closedAt", header: t("Closed"), kind: "muted", size: 130 },
      ]}
      facet={{ key: "status", label: t("Status"), values: statuses }}
      sorts={[
        { value: "newest", label: t("Newest first") },
        { value: "oldest", label: t("Oldest first") },
      ]}
      searchLabel={t("Search notes")}
      errorTitle={t("The sessions didn't load")}
      emptyIcon={<CoinsIcon />}
      emptyTitle={t("No sessions found")}
      emptyDescription={t(
        "Open a session with its float, then count the drawer at the end of the day, or change the filters.",
      )}
    />
  );
}

/** The tills of the organization and whether each has a shift open. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function TillOverview({ query }: { query: RecordListUrlQuery }) {
  await requirePermission("tills.read");

  const [t, openIds, canManage] = await Promise.all([
    getExtracted("tills"),
    loadOpenTillIds(),
    holds("tills.manage"),
  ]);

  const states = {
    open: t("Shift open"),
    idle: t("Idle"),
    archived: t("Archived"),
  };

  const open = new Set(openIds);

  return (
    <BlockOverview
      pager={({ db }) => ({
        page: (options) =>
          db.tills.tillPage({
            ...options,
            filters: { ...options.filters, includeArchived: ["true"] },
          }),
        facets: (options) =>
          db.tills.tillFacets({
            ...options,
            filters: { ...options.filters, includeArchived: ["true"] },
          }),
      })}
      map={{
        sorts: { name: { by: "name" } },
        filters: { f: "currency" },
        facets: { f: "currency" },
      }}
      query={query}
      toRow={(till) => ({
        id: till.id,
        name: till.name,
        location: till.location ?? null,
        currency: till.currency,
        books: till.accountId === undefined ? "none" : "linked",
        state:
          till.archivedAt === undefined
            ? open.has(till.id)
              ? "open"
              : "idle"
            : "archived",
      })}
      columns={[
        { key: "name", header: t("Till"), kind: "text", size: 240 },
        { key: "location", header: t("Location"), kind: "muted", size: 160 },
        { key: "currency", header: t("Currency"), kind: "muted", size: 100 },
        {
          key: "books",
          header: t("Cash account"),
          kind: "badge",
          size: 140,
          labels: { linked: t("In the chart"), none: t("Not linked") },
          tones: { linked: "success-light" },
        },
        {
          key: "state",
          header: t("Status"),
          kind: "badge",
          size: 120,
          labels: states,
          tones: { open: "info-light" },
        },
      ]}
      facet={{
        key: "currency",
        label: t("Currency"),
        values: { EUR: "EUR", USD: "USD", GBP: "GBP" },
      }}
      sorts={[{ value: "name", label: t("Name") }]}
      searchLabel={t("Search tills")}
      errorTitle={t("The tills didn't load")}
      emptyIcon={<StoreIcon />}
      emptyTitle={t("No tills yet")}
      emptyDescription={t(
        "A till keeps its cash in the accounting chart, so the closing count books any difference.",
      )}
      emptyAction={canManage ? <NewTillDialog /> : undefined}
    />
  );
}

// skeleton: renders from props and translations, so nothing of its own suspends
export async function NewTillDialog() {
  const t = await getExtracted("tills");

  return (
    <ActionDialog
      action={createTill}
      title={t("Add a till")}
      description={t(
        "The till gets a cash account in the chart so its counts book to accounting.",
      )}
      trigger={t("Add till")}
      submitLabel={t("Add till")}
      successMessage={t("Till added")}
      variant="outline"
      fields={[
        {
          name: "name",
          label: t("Name"),
          kind: "text",
          required: true,
          placeholder: t("Front counter"),
        },
      ]}
    />
  );
}

// skeleton: the page's Suspense fallback is the skeleton of this view
export async function OpenSessionDialog() {
  const [t, loaded] = await Promise.all([
    getExtracted("tills"),
    settle(loadTills),
  ]);

  const idle =
    loaded.kind === "ok"
      ? loaded.data.filter((till) => !till.archived && !till.open)
      : [];

  if (idle.length === 0) {
    return null;
  }

  return (
    <ActionDialog
      action={openSession}
      title={t("Open a session")}
      description={t("A till has one open session at a time.")}
      trigger={t("Open session")}
      submitLabel={t("Open session")}
      successMessage={t("Session opened")}
      redirectTo="/tills/{id}"
      hidden={{ currency: "EUR" }}
      fields={[
        {
          name: "tillId",
          label: t("Till"),
          kind: "select",
          options: idle.map((till) => ({ value: till.id, label: till.name })),
        },
        {
          name: "openingFloat",
          label: t("Opening float (EUR)"),
          kind: "decimal",
          defaultValue: "100.00",
        },
        { name: "notes", label: t("Notes"), kind: "text" },
      ]}
    />
  );
}
