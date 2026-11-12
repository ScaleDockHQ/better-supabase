import { CoinsIcon, StoreIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { BlockListQuery } from "@/lib/array-list";

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
import { loadSessions, loadTills } from "../tills-queries";

export function TillsListSkeleton() {
  return <RecordListSkeleton rows={5} />;
}

/** Shifts, searched by till, filtered by status, sorted and paged on the server. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function SessionOverview({ query }: { query: BlockListQuery }) {
  await requirePermission("tills.read");

  const [t, loaded, fmtDate, fmtMoney] = await Promise.all([
    getExtracted("tills"),
    settle(loadSessions),
    dateFormatter(),
    moneyFormatter(),
  ]);

  const statuses = { open: t("Open"), closed: t("Closed") };

  return (
    <BlockOverview
      loaded={loaded}
      query={query}
      spec={{
        search: (row) => row.till,
        facet: (row) => row.status,
        defaultSort: "newest",
        sorts: {
          newest: (a, b) => b.openedAt.localeCompare(a.openedAt),
          oldest: (a, b) => a.openedAt.localeCompare(b.openedAt),
          expected: (a, b) =>
            Number(b.expected.amount) - Number(a.expected.amount),
        },
      }}
      toRow={(row) => ({
        id: row.id,
        till: row.till,
        status: row.status,
        openingFloat: fmtMoney(row.openingFloat),
        expected: fmtMoney(row.expected),
        openedAt: fmtDate(row.openedAt),
        closedAt: fmtDate(row.closedAt),
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
        { value: "expected", label: t("Most cash") },
      ]}
      searchLabel={t("Search by till")}
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
export async function TillOverview({ query }: { query: BlockListQuery }) {
  await requirePermission("tills.read");

  const [t, loaded, canManage] = await Promise.all([
    getExtracted("tills"),
    settle(loadTills),
    holds("tills.manage"),
  ]);

  const states = {
    open: t("Shift open"),
    idle: t("Idle"),
    archived: t("Archived"),
  };

  return (
    <BlockOverview
      loaded={loaded}
      query={query}
      spec={{
        search: (till) => `${till.name} ${till.location ?? ""}`,
        facet: (till) =>
          till.archived ? "archived" : till.open ? "open" : "idle",
        defaultSort: "name",
        sorts: { name: (a, b) => a.name.localeCompare(b.name) },
      }}
      toRow={(till) => ({
        id: till.id,
        name: till.name,
        location: till.location,
        currency: till.currency,
        books: till.hasAccount ? "linked" : "none",
        state: till.archived ? "archived" : till.open ? "open" : "idle",
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
      facet={{ key: "state", label: t("Status"), values: states }}
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
