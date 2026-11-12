/* oxlint-disable anti-slop/no-unknown-parameters, anti-slop/no-runtime-typeof -- `asText` reads one cell of the untyped jsonb row `api.finance_list` sends; 3 findings */
"use client";

import type { CellContext } from "@tanstack/react-table";
import type { ReactNode } from "react";

import { formatMoney, moneyFromJson } from "better-supabase/commerce";
import { useRecordListState } from "better-supabase/react";
import {
  BanknoteIcon,
  CalendarClockIcon,
  ClockIcon,
  ReceiptIcon,
  ScaleIcon,
  WalletIcon,
} from "lucide-react";
import { useExtracted, useFormatter, useLocale } from "next-intl";
import { createParser, useQueryStates } from "nuqs";
import { createContext, use, useMemo } from "react";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type {
  RecordListFacet,
  RecordListPage,
  RecordListSort,
} from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";
import type { FinanceEntityKey } from "@/lib/finance-list";

import { RecordListView } from "@/components/record-list/record-list-view";
import { Badge } from "@/components/reui/badge";
import { Link } from "@/i18n/navigation";
import { FINANCE_ENTITIES, defineFinanceList } from "@/lib/finance-list";

import type { FinanceRow } from "../finance-records-types";

import { financeRecordPath } from "../finance-records-paths";
import { statusVariant } from "../finance-records-status";

type Cell = CellContext<ReadOnlyGridFeatures, FinanceRow>;

type ColumnKind =
  | "link"
  | "text"
  | "date"
  | "datetime"
  | "money"
  | "status"
  | "number"
  | "yesno"
  | "duration"
  | "label";

interface ColumnSpec {
  readonly key: string;
  readonly header: string;
  readonly kind: ColumnKind;
  readonly size: number;
}

/** The entity a grid's link cells point into. */
const EntityContext = createContext<FinanceEntityKey>("invoices");

const asText = (value: unknown): string | null =>
  typeof value === "string" || typeof value === "number" ? String(value) : null;

/** `partially_paid` as "Partially paid", for a value the app has no label for. */
const humanize = (value: string): string => {
  const spaced = value.replaceAll(/[_-]/g, " ");

  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
};

function useValueLabel(): (value: string) => string {
  const t = useExtracted("finance");

  return (value) => {
    switch (value) {
      case "draft": {
        return t("Draft");
      }

      case "issued": {
        return t("Issued");
      }

      case "partially_paid": {
        return t("Partly paid");
      }

      case "paid": {
        return t("Paid");
      }

      case "void": {
        return t("Void");
      }

      case "uncollectible": {
        return t("Uncollectible");
      }

      case "submitted": {
        return t("Submitted");
      }

      case "approved": {
        return t("Approved");
      }

      case "reimbursed": {
        return t("Reimbursed");
      }

      case "cancelled": {
        return t("Cancelled");
      }

      case "open": {
        return t("Open");
      }

      case "locked": {
        return t("Locked");
      }

      case "closed": {
        return t("Closed");
      }

      case "filed": {
        return t("Filed");
      }

      case "exported": {
        return t("Exported");
      }

      case "posted": {
        return t("Posted");
      }

      case "active": {
        return t("Active");
      }

      case "archived": {
        return t("Archived");
      }

      case "matched": {
        return t("Matched");
      }

      case "unmatched": {
        return t("Unmatched");
      }

      case "ignored": {
        return t("Ignored");
      }

      case "sales": {
        return t("Sales");
      }

      case "purchase": {
        return t("Purchase");
      }

      case "true": {
        return t("Yes");
      }

      case "false": {
        return t("No");
      }

      default: {
        return humanize(value);
      }
    }
  };
}

function LinkCell({ row, column }: Cell) {
  const entity = use(EntityContext);
  const value = asText(row.original[column.id]);

  return (
    // The record reads `params`, which the shared App Shell can't carry; a
    // per-link prefetch resolves its cached reads.
    <Link
      href={financeRecordPath(entity, row.original.id)}
      prefetch
      className="font-medium hover:underline"
    >
      {value ?? row.original.id.slice(0, 8)}
    </Link>
  );
}

function TextCell({ row, column }: Cell) {
  return (
    <span className="text-muted-foreground">
      {asText(row.original[column.id]) ?? "–"}
    </span>
  );
}

function LabelCell({ row, column }: Cell) {
  const label = useValueLabel();
  const value = asText(row.original[column.id]);

  return (
    <span className="text-muted-foreground">
      {value === null ? "–" : label(value)}
    </span>
  );
}

function NumberCell({ row, column }: Cell) {
  return (
    <span className="tabular-nums">
      {asText(row.original[column.id]) ?? "–"}
    </span>
  );
}

function DateCell({ row, column }: Cell) {
  const format = useFormatter();
  const value = asText(row.original[column.id]);

  return (
    <span className="text-muted-foreground">
      {value
        ? format.dateTime(new Date(value), {
            dateStyle: "medium",
            timeZone: "UTC",
          })
        : "–"}
    </span>
  );
}

function DateTimeCell({ row, column }: Cell) {
  const format = useFormatter();
  const value = asText(row.original[column.id]);

  return (
    <span className="text-muted-foreground">
      {value
        ? format.dateTime(new Date(value), {
            dateStyle: "medium",
            timeStyle: "short",
          })
        : "–"}
    </span>
  );
}

function MoneyCell({ row, column }: Cell) {
  const locale = useLocale();
  const amount = asText(row.original[column.id]);
  const currency = asText(row.original["currency"]);

  return (
    <span className="tabular-nums">
      {amount !== null && currency !== null
        ? formatMoney(moneyFromJson({ amount, currency }), locale)
        : "–"}
    </span>
  );
}

function StatusCell({ row, column }: Cell) {
  const label = useValueLabel();
  const value = asText(row.original[column.id]);

  return value === null ? null : (
    <Badge variant={statusVariant(value)}>{label(value)}</Badge>
  );
}

function YesNoCell({ row, column }: Cell) {
  const t = useExtracted("finance");

  return (
    <span className="text-muted-foreground">
      {row.original[column.id] === true ? t("Yes") : t("No")}
    </span>
  );
}

function DurationCell({ row, column }: Cell) {
  const seconds = Number(row.original[column.id] ?? 0);
  const minutes = Math.round(seconds / 60);

  return (
    <span className="tabular-nums">
      {Math.floor(minutes / 60)}h {String(minutes % 60).padStart(2, "0")}m
    </span>
  );
}

const CELLS = {
  link: LinkCell,
  text: TextCell,
  label: LabelCell,
  number: NumberCell,
  date: DateCell,
  datetime: DateTimeCell,
  money: MoneyCell,
  status: StatusCell,
  yesno: YesNoCell,
  duration: DurationCell,
} as const satisfies Readonly<Record<ColumnKind, (cell: Cell) => ReactNode>>;

/** The columns, the filters, the sorts and the words of one entity's overview. */
function useEntityCopy(entity: FinanceEntityKey) {
  const t = useExtracted("finance");
  const label = useValueLabel();

  const status: RecordListFacet = {
    key: "status",
    label: t("Status"),
    valueLabel: label,
  };

  const humanized = (key: string, text: string): RecordListFacet => ({
    key,
    label: text,
    valueLabel: label,
  });

  switch (entity) {
    case "invoices":
    case "payables": {
      const payable = entity === "payables";

      return {
        icon: <ReceiptIcon />,
        search: payable ? t("Search bills") : t("Search invoices"),
        empty: payable ? t("No bills found") : t("No invoices found"),
        emptyText: t("Invoices show up here once they are created."),
        columns: [
          { key: "title", header: t("Title"), kind: "link", size: 280 },
          { key: "identifier", header: t("Number"), kind: "text", size: 120 },
          { key: "status", header: t("Status"), kind: "status", size: 130 },
          ...(payable
            ? []
            : ([
                {
                  key: "direction",
                  header: t("Direction"),
                  kind: "label",
                  size: 110,
                },
              ] satisfies ColumnSpec[])),
          { key: "dueOn", header: t("Due"), kind: "date", size: 130 },
          { key: "total", header: t("Total"), kind: "money", size: 130 },
          { key: "balance", header: t("Owed"), kind: "money", size: 130 },
        ] satisfies ColumnSpec[],
        facets: [
          status,
          ...(payable ? [] : [humanized("direction", t("Direction"))]),
        ],
        sorts: [
          { value: "default", label: t("Newest first") },
          { value: "due", label: t("Due date") },
          { value: "total", label: t("Largest total") },
        ],
      };
    }

    case "expenses": {
      return {
        icon: <WalletIcon />,
        search: t("Search expense reports"),
        empty: t("No expense reports found"),
        emptyText: t("Reports show up here once someone files them."),
        columns: [
          { key: "title", header: t("Report"), kind: "link", size: 300 },
          { key: "status", header: t("Status"), kind: "status", size: 130 },
          { key: "lines", header: t("Receipts"), kind: "number", size: 100 },
          { key: "total", header: t("Total"), kind: "money", size: 130 },
          {
            key: "submittedAt",
            header: t("Submitted"),
            kind: "datetime",
            size: 170,
          },
        ] satisfies ColumnSpec[],
        facets: [status],
        sorts: [
          { value: "default", label: t("Newest first") },
          { value: "total", label: t("Largest total") },
        ],
      };
    }

    case "ledger": {
      return {
        icon: <ScaleIcon />,
        search: t("Search transactions"),
        empty: t("No ledger transactions found"),
        emptyText: t(
          "Postings show up here once a block writes to the ledger.",
        ),
        columns: [
          { key: "memo", header: t("Memo"), kind: "link", size: 320 },
          { key: "kind", header: t("Kind"), kind: "label", size: 140 },
          { key: "entries", header: t("Entries"), kind: "number", size: 100 },
          {
            key: "effectiveAt",
            header: t("Effective"),
            kind: "datetime",
            size: 170,
          },
        ] satisfies ColumnSpec[],
        facets: [humanized("kind", t("Kind"))],
        sorts: [
          { value: "default", label: t("Newest first") },
          { value: "oldest", label: t("Oldest first") },
        ],
      };
    }

    case "journal": {
      return {
        icon: <ScaleIcon />,
        search: t("Search journal entries"),
        empty: t("No journal entries found"),
        emptyText: t("Entries show up here once they are posted."),
        columns: [
          { key: "number", header: t("Entry"), kind: "link", size: 160 },
          { key: "entryDate", header: t("Date"), kind: "date", size: 130 },
          { key: "memo", header: t("Memo"), kind: "text", size: 280 },
          { key: "status", header: t("Status"), kind: "status", size: 120 },
          { key: "sourceType", header: t("Source"), kind: "label", size: 130 },
          { key: "total", header: t("Debit"), kind: "money", size: 130 },
        ] satisfies ColumnSpec[],
        facets: [status, humanized("sourceType", t("Source"))],
        sorts: [
          { value: "default", label: t("Newest first") },
          { value: "oldest", label: t("Oldest first") },
        ],
      };
    }

    case "billable-time": {
      return {
        icon: <ClockIcon />,
        search: t("Search time entries"),
        empty: t("No time entries found"),
        emptyText: t("Logged time shows up here."),
        columns: [
          { key: "note", header: t("Note"), kind: "link", size: 280 },
          {
            key: "startedAt",
            header: t("Started"),
            kind: "datetime",
            size: 170,
          },
          {
            key: "seconds",
            header: t("Duration"),
            kind: "duration",
            size: 100,
          },
          { key: "billable", header: t("Billable"), kind: "yesno", size: 100 },
          { key: "billed", header: t("Invoiced"), kind: "yesno", size: 100 },
          { key: "rate", header: t("Hourly rate"), kind: "money", size: 130 },
        ] satisfies ColumnSpec[],
        facets: [
          humanized("billable", t("Billable")),
          humanized("billed", t("Invoiced")),
        ],
        sorts: [
          { value: "default", label: t("Newest first") },
          { value: "longest", label: t("Longest first") },
        ],
      };
    }

    case "recurring": {
      return {
        icon: <CalendarClockIcon />,
        search: t("Search schedules"),
        empty: t("No schedules found"),
        emptyText: t("Deferrals and recurring postings show up here."),
        columns: [
          { key: "sourceId", header: t("Source"), kind: "link", size: 240 },
          { key: "sourceType", header: t("Type"), kind: "label", size: 130 },
          { key: "startsOn", header: t("Starts"), kind: "date", size: 130 },
          { key: "endsOn", header: t("Ends"), kind: "date", size: 130 },
          { key: "amount", header: t("Amount"), kind: "money", size: 130 },
          { key: "posted", header: t("Posted"), kind: "number", size: 90 },
        ] satisfies ColumnSpec[],
        facets: [humanized("sourceType", t("Type"))],
        sorts: [
          { value: "default", label: t("Newest first") },
          { value: "amount", label: t("Largest amount") },
        ],
      };
    }

    case "tax": {
      return {
        icon: <ReceiptIcon />,
        search: t("Search tax returns"),
        empty: t("No tax returns found"),
        emptyText: t("Prepare a return for a period to see it here."),
        columns: [
          { key: "period", header: t("Period"), kind: "link", size: 200 },
          { key: "status", header: t("Status"), kind: "status", size: 120 },
          { key: "periodStart", header: t("From"), kind: "date", size: 130 },
          { key: "periodEnd", header: t("To"), kind: "date", size: 130 },
          { key: "filedAt", header: t("Filed"), kind: "datetime", size: 170 },
        ] satisfies ColumnSpec[],
        facets: [status],
        sorts: [
          { value: "default", label: t("Newest first") },
          { value: "oldest", label: t("Oldest first") },
        ],
      };
    }

    case "periods": {
      return {
        icon: <CalendarClockIcon />,
        search: t("Search periods"),
        empty: t("No periods found"),
        emptyText: t("Periods are created the first time a date needs one."),
        columns: [
          { key: "startsOn", header: t("Starts"), kind: "link", size: 160 },
          { key: "endsOn", header: t("Ends"), kind: "date", size: 130 },
          { key: "kind", header: t("Kind"), kind: "label", size: 160 },
          { key: "status", header: t("Status"), kind: "status", size: 120 },
          { key: "closedAt", header: t("Closed"), kind: "datetime", size: 170 },
        ] satisfies ColumnSpec[],
        facets: [status, humanized("kind", t("Kind"))],
        sorts: [
          { value: "default", label: t("Newest first") },
          { value: "oldest", label: t("Oldest first") },
        ],
      };
    }

    case "payroll": {
      return {
        icon: <BanknoteIcon />,
        search: t("Search payroll runs"),
        empty: t("No payroll runs found"),
        emptyText: t("Create a run for a period to collect worked hours."),
        columns: [
          { key: "label", header: t("Run"), kind: "link", size: 240 },
          { key: "periodFrom", header: t("From"), kind: "date", size: 130 },
          { key: "periodTo", header: t("To"), kind: "date", size: 130 },
          { key: "status", header: t("Status"), kind: "status", size: 120 },
          { key: "lines", header: t("Lines"), kind: "number", size: 90 },
        ] satisfies ColumnSpec[],
        facets: [status],
        sorts: [
          { value: "default", label: t("Newest period") },
          { value: "oldest", label: t("Oldest period") },
        ],
      };
    }

    case "legal-entities": {
      return {
        icon: <ScaleIcon />,
        search: t("Search legal entities"),
        empty: t("No legal entities found"),
        emptyText: t("Add the companies your organization invoices from."),
        columns: [
          { key: "name", header: t("Name"), kind: "link", size: 280 },
          { key: "code", header: t("Code"), kind: "text", size: 120 },
          {
            key: "vatNumber",
            header: t("VAT number"),
            kind: "text",
            size: 170,
          },
          { key: "currency", header: t("Currency"), kind: "text", size: 100 },
          { key: "isDefault", header: t("Default"), kind: "yesno", size: 100 },
        ] satisfies ColumnSpec[],
        facets: [humanized("state", t("State"))],
        sorts: [
          { value: "default", label: t("Code") },
          { value: "newest", label: t("Newest first") },
        ],
      };
    }

    case "funding": {
      return {
        icon: <BanknoteIcon />,
        search: t("Search awards"),
        empty: t("No awards found"),
        emptyText: t("Awards show up here once a funder grants units."),
        columns: [
          { key: "reference", header: t("Reference"), kind: "link", size: 220 },
          { key: "subjectType", header: t("Record"), kind: "label", size: 130 },
          { key: "status", header: t("Status"), kind: "status", size: 120 },
          { key: "period", header: t("Period"), kind: "label", size: 110 },
          { key: "used", header: t("Used"), kind: "number", size: 90 },
          { key: "units", header: t("Units"), kind: "number", size: 90 },
          { key: "endsOn", header: t("Ends"), kind: "date", size: 130 },
        ] satisfies ColumnSpec[],
        facets: [status, humanized("period", t("Period"))],
        sorts: [
          { value: "default", label: t("Newest first") },
          { value: "units", label: t("Most units") },
        ],
      };
    }

    case "bank-accounts": {
      return {
        icon: <WalletIcon />,
        search: t("Search accounts"),
        empty: t("No bank accounts found"),
        emptyText: t("Add an account to import statements."),
        columns: [
          { key: "name", header: t("Name"), kind: "link", size: 260 },
          { key: "iban", header: t("IBAN"), kind: "text", size: 220 },
          { key: "currency", header: t("Currency"), kind: "text", size: 100 },
          { key: "holder", header: t("Holder"), kind: "text", size: 200 },
          { key: "isPrimary", header: t("Primary"), kind: "yesno", size: 100 },
        ] satisfies ColumnSpec[],
        facets: [humanized("currency", t("Currency"))],
        sorts: [
          { value: "default", label: t("Name") },
          { value: "newest", label: t("Newest first") },
        ],
      };
    }

    case "bank-transactions": {
      return {
        icon: <WalletIcon />,
        search: t("Search transactions"),
        empty: t("No bank transactions found"),
        emptyText: t("Import a statement to see transactions here."),
        columns: [
          {
            key: "counterparty",
            header: t("Counterparty"),
            kind: "link",
            size: 240,
          },
          { key: "account", header: t("Account"), kind: "text", size: 180 },
          { key: "bookedOn", header: t("Booked"), kind: "date", size: 130 },
          { key: "amount", header: t("Amount"), kind: "money", size: 130 },
          { key: "status", header: t("Status"), kind: "status", size: 120 },
          {
            key: "remittance",
            header: t("Remittance"),
            kind: "text",
            size: 240,
          },
        ] satisfies ColumnSpec[],
        facets: [status],
        sorts: [
          { value: "default", label: t("Newest first") },
          { value: "amount", label: t("Largest amount") },
        ],
      };
    }

    default: {
      const unknown: never = entity;

      return unknown;
    }
  }
}

/**
 * One finance entity's overview on the list kit: the URL holds the search, the
 * filters, the sort and the cursor, and the entity's list route serves every
 * state but the default page, which the server renders.
 */
export function FinanceRecordList({
  entity,
  initial,
  emptyAction,
}: {
  entity: FinanceEntityKey;
  initial: RecordListPage<FinanceRow>;
  /** The create action beside Reset when nothing matches. */
  emptyAction?: ReactNode;
}) {
  const copy = useEntityCopy(entity);
  const list = useMemo(() => defineFinanceList(entity), [entity]);

  const state = useRecordListState(
    list,
    useQueryStates(list.nuqs(createParser)),
  );

  const columns: RecordListColumns<FinanceRow> = copy.columns.map((spec) => ({
    accessorKey: spec.key,
    header: spec.header,
    size: spec.size,
    cell: CELLS[spec.kind],
  }));

  const facets: readonly RecordListFacet[] = copy.facets;
  const sorts: readonly RecordListSort[] = copy.sorts;

  return (
    <EntityContext value={entity}>
      <RecordListView
        list={state}
        endpoint={FINANCE_ENTITIES[entity].endpoint}
        initial={initial}
        columns={columns}
        facets={facets}
        sorts={sorts}
        searchLabel={copy.search}
        emptyIcon={copy.icon}
        emptyTitle={copy.empty}
        emptyDescription={copy.emptyText}
        emptyAction={emptyAction}
      />
    </EntityContext>
  );
}
