import type { ReactNode } from "react";

import { formatMoney, moneyFromJson } from "better-supabase/commerce";
import { TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter, getLocale } from "next-intl/server";
import { notFound } from "next/navigation";
import { refresh } from "next/cache";

import type { FinanceEntityKey } from "@/lib/finance-list";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getFinanceRecord } from "../finance-records-queries";
import { statusVariant } from "../finance-records-status";
import {
  ExpenseActions,
  FundingActions,
  InvoiceActions,
  LegalEntityActions,
  PayableActions,
  PeriodActions,
  RefreshPayrollRunButton,
  TaxReturnActions,
} from "./finance-record-actions";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

type Fields = readonly { readonly label: string; readonly value: string }[];

interface TableView {
  readonly title: string;
  readonly headers: readonly string[];
  readonly rows: readonly (readonly string[])[];
  readonly empty: string;
}

interface View {
  readonly title: string;
  readonly description?: string;
  readonly status?: string;
  readonly actions?: ReactNode;
  readonly fields: Fields;
  readonly tables: readonly TableView[];
}

type Json = Readonly<Record<string, unknown>>;

const asText = (value: unknown): string | null =>
  typeof value === "string" || typeof value === "number"
    ? String(value)
    : typeof value === "boolean"
      ? String(value)
      : null;

const rowsOf = (value: unknown): readonly Json[] =>
  Array.isArray(value)
    ? value.filter(
        (row): row is Json => typeof row === "object" && row !== null,
      )
    : [];

const humanize = (value: string): string => {
  const spaced = value.replaceAll(/[_-]/g, " ");

  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
};

/** The whole record page of one finance entity, for the page's `<Suspense>`. */
export async function FinanceDetail({
  entity,
  id,
}: {
  entity: FinanceEntityKey;
  id: string;
}) {
  const [loaded, t, format, locale, permissions] = await Promise.all([
    getFinanceRecord(entity, id),
    getExtracted("finance"),
    getFormatter(),
    getLocale(),
    getPermissions(),
  ]);

  if (loaded.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The record did not load")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
        <AlertAction>
          <form action={retry}>
            <Button size="sm" variant="outline" type="submit">
              {t("Retry")}
            </Button>
          </form>
        </AlertAction>
      </Alert>
    );
  }

  if (loaded.kind === "no-organization") {
    notFound();
  }

  const record = loaded.data;
  const text = (key: string): string => asText(record[key]) ?? "";
  const dash = (value: string | null): string => value ?? "–";

  const date = (value: unknown): string => {
    const raw = asText(value);

    return raw
      ? format.dateTime(new Date(raw), { dateStyle: "medium", timeZone: "UTC" })
      : "–";
  };

  const dateTime = (value: unknown): string => {
    const raw = asText(value);

    return raw
      ? format.dateTime(new Date(raw), {
          dateStyle: "medium",
          timeStyle: "short",
        })
      : "–";
  };

  const money = (amount: unknown, currency: unknown): string => {
    const value = asText(amount);
    const code = asText(currency);

    return value !== null && code !== null
      ? formatMoney(moneyFromJson({ amount: value, currency: code }), locale)
      : "–";
  };

  const yesNo = (value: unknown): string => (value === true ? t("Yes") : t("No"));

  const duration = (value: unknown): string => {
    const minutes = Math.round(Number(value ?? 0) / 60);

    return `${String(Math.floor(minutes / 60))}h ${String(minutes % 60).padStart(2, "0")}m`;
  };

  const statusText = (value: string): string => {
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
      default: {
        return humanize(value);
      }
    }
  };

  const currency = text("currency");

  const view = ((): View => {
    switch (entity) {
      case "invoices":
      case "payables": {
        const status = text("status");

        return {
          title: text("title"),
          description: dash(asText(record["identifier"])),
          status,
          actions:
            entity === "payables" ? (
              <PayableActions
                invoiceId={id}
                status={status}
                canApprove={can(permissions, "invoices.approve")}
              />
            ) : (
              <InvoiceActions
                invoiceId={id}
                status={status}
                currency={currency}
                canWrite={can(permissions, "invoices.write")}
              />
            ),
          fields: [
            { label: t("Direction"), value: humanize(text("direction")) },
            { label: t("Issued"), value: date(record["issued_on"]) },
            { label: t("Due"), value: date(record["due_on"]) },
            { label: t("Subtotal"), value: money(record["subtotal"], currency) },
            { label: t("Tax"), value: money(record["tax_total"], currency) },
            { label: t("Total"), value: money(record["total"], currency) },
            { label: t("Paid"), value: money(record["paid_total"], currency) },
            {
              label: t("Credited"),
              value: money(record["credited_total"], currency),
            },
            { label: t("Reminder level"), value: text("dunning_level") },
            {
              label: t("Supplier reference"),
              value: dash(asText(record["supplier_reference"])),
            },
          ],
          tables: [
            {
              title: t("Lines"),
              headers: [t("Description"), t("Quantity"), t("Unit amount"), t("Tax")],
              rows: rowsOf(record["lines"]).map((line) => [
                text_(line, "description"),
                text_(line, "quantity"),
                money(line["unit_amount"], currency),
                `${String(Number(line["tax_rate_bps"] ?? 0) / 100)}%`,
              ]),
              empty: t("No lines."),
            },
            {
              title: t("Reminders"),
              headers: [t("Date"), t("Level"), t("Fee"), t("Open balance")],
              rows: rowsOf(record["dunning"]).map((row) => [
                dateTime(row["created_at"]),
                text_(row, "level"),
                money(row["fee"], currency),
                money(row["balance"], currency),
              ]),
              empty: t("No reminders were sent."),
            },
            {
              title: t("E-invoice deliveries"),
              headers: [t("Date"), t("Channel"), t("Format"), t("State")],
              rows: rowsOf(record["deliveries"]).map((row) => [
                dateTime(row["created_at"]),
                humanize(text_(row, "channel")),
                text_(row, "format"),
                humanize(text_(row, "state")),
              ]),
              empty: t("Not sent as an e-invoice."),
            },
            {
              title: t("Bank matches"),
              headers: [t("Booked"), t("Counterparty"), t("Amount")],
              rows: rowsOf(record["matches"]).map((row) => [
                date(row["bookedOn"]),
                text_(row, "counterparty"),
                money(row["amount"], currency),
              ]),
              empty: t("No bank transaction pays this invoice yet."),
            },
          ],
        };
      }
      case "expenses": {
        const lines = rowsOf(record["lines"]);

        const status = ((): string => {
          if (record["cancelled_at"]) {
            return "cancelled";
          }

          if (record["reimbursed_at"]) {
            return "reimbursed";
          }

          if (record["approved_at"]) {
            return "approved";
          }

          return record["submitted_at"] ? "submitted" : "draft";
        })();

        return {
          title: text("title"),
          description: dash(asText(record["note"])),
          status,
          actions: (
            <ExpenseActions
              reportId={id}
              status={status}
              canSubmit={can(permissions, "expenses.submit")}
              canApprove={can(permissions, "expenses.approve")}
              canManage={can(permissions, "expenses.manage")}
            />
          ),
          fields: [
            { label: t("Filed"), value: dateTime(record["created_at"]) },
            { label: t("Submitted"), value: dateTime(record["submitted_at"]) },
            { label: t("Approved"), value: dateTime(record["approved_at"]) },
            { label: t("Reimbursed"), value: dateTime(record["reimbursed_at"]) },
            { label: t("Currency"), value: currency },
          ],
          tables: [
            {
              title: t("Receipts"),
              headers: [t("Date"), t("Description"), t("Category"), t("Amount")],
              rows: lines.map((line) => [
                date(line["spent_on"]),
                text_(line, "description"),
                text_(line, "category"),
                money(line["amount"], currency),
              ]),
              empty: t("No receipts on this report."),
            },
          ],
        };
      }
      case "ledger": {
        return {
          title: text("memo") || t("Ledger transaction"),
          description: humanize(text("kind")),
          fields: [
            { label: t("Effective"), value: dateTime(record["effective_at"]) },
            { label: t("Kind"), value: humanize(text("kind")) },
            {
              label: t("Reference"),
              value: dash(asText(record["reference_id"])),
            },
          ],
          tables: [
            {
              title: t("Entries"),
              headers: [t("Account"), t("Amount"), t("Unit")],
              rows: rowsOf(record["entries"]).map((row) => [
                `${text_(row, "code")} ${text_(row, "account")}`.trim(),
                text_(row, "amount"),
                text_(row, "unit"),
              ]),
              empty: t("No entries."),
            },
          ],
        };
      }
      case "journal": {
        const lines = rowsOf(record["lines"]);
        const code = asText(lines[0]?.["currency"]) ?? "EUR";

        return {
          title: t("Entry {number}", { number: text("number") }),
          description: dash(asText(record["memo"])),
          status: text("status"),
          fields: [
            { label: t("Date"), value: date(record["entry_date"]) },
            { label: t("Reference"), value: dash(asText(record["reference"])) },
            {
              label: t("Source"),
              value: dash(asText(record["source_type"])),
            },
            { label: t("Posted"), value: dateTime(record["posted_at"]) },
          ],
          tables: [
            {
              title: t("Lines"),
              headers: [t("Account"), t("Debit"), t("Credit"), t("Description")],
              rows: lines.map((line) => [
                `${text_(line, "code")} ${text_(line, "account")}`.trim(),
                money(line["debit"], code),
                money(line["credit"], code),
                text_(line, "description"),
              ]),
              empty: t("No lines."),
            },
          ],
        };
      }
      case "billable-time": {
        return {
          title: dash(asText(record["note"])),
          description: dateTime(record["started_at"]),
          fields: [
            { label: t("Started"), value: dateTime(record["started_at"]) },
            { label: t("Ended"), value: dateTime(record["ended_at"]) },
            { label: t("Duration"), value: duration(record["seconds"]) },
            { label: t("Billable"), value: yesNo(record["billable"]) },
            {
              label: t("Hourly rate"),
              value: money(record["rate"], record["rate_currency"]),
            },
            { label: t("Record"), value: `${text("subject_type")} ${text("subject_id")}`.trim() },
          ],
          tables: [
            {
              title: t("Invoiced on"),
              headers: [t("Invoice"), t("Hours billed"), t("Rate")],
              rows: rowsOf(record["invoices"]).map((row) => [
                text_(row, "invoiceId").slice(0, 8),
                duration(row["seconds"]),
                money(row["rate"], row["currency"]),
              ]),
              empty: t("Not invoiced yet."),
            },
          ],
        };
      }
      case "recurring": {
        return {
          title: text("source_id"),
          description: humanize(text("source_type")),
          fields: [
            { label: t("Amount"), value: money(record["amount"], currency) },
            { label: t("Starts"), value: date(record["starts_on"]) },
            { label: t("Ends"), value: date(record["ends_on"]) },
            { label: t("Line"), value: dash(asText(record["line_ref"])) },
          ],
          tables: [
            {
              title: t("Postings"),
              headers: [t("Due"), t("Amount"), t("Status")],
              rows: rowsOf(record["rows"]).map((row) => [
                date(row["due_on"]),
                money(row["amount"], currency),
                statusText(text_(row, "status")),
              ]),
              empty: t("No postings are planned."),
            },
          ],
        };
      }
      case "tax": {
        const status = text("status");
        const boxes = record["boxes"];

        return {
          title: text("period"),
          description: `${date(record["period_start"])} – ${date(record["period_end"])}`,
          status,
          actions: can(permissions, "tax.manage") ? (
            <TaxReturnActions returnId={id} status={status} />
          ) : null,
          fields: [
            { label: t("Prepared"), value: dateTime(record["prepared_at"]) },
            { label: t("Filed"), value: dateTime(record["filed_at"]) },
            { label: t("Currency"), value: dash(asText(record["currency"])) },
          ],
          tables: [
            {
              title: t("Boxes"),
              headers: [t("Box"), t("Amount")],
              rows:
                typeof boxes === "object" && boxes !== null
                  ? Object.entries(boxes).map(([box, amount]) => [
                      box,
                      money(amount, currency),
                    ])
                  : [],
              empty: t("The return has no boxes."),
            },
          ],
        };
      }
      case "periods": {
        const status = text("status");

        return {
          title: `${date(record["starts_on"])} – ${date(record["ends_on"])}`,
          description: humanize(text("kind")),
          status,
          actions: can(permissions, "periods.write") ? (
            <PeriodActions periodId={id} status={status} />
          ) : null,
          fields: [
            { label: t("Kind"), value: humanize(text("kind")) },
            { label: t("Closed"), value: dateTime(record["closed_at"]) },
          ],
          tables: [],
        };
      }
      case "payroll": {
        const status = text("status");

        return {
          title: text("label") || t("Payroll run"),
          description: `${date(record["period_from"])} – ${date(record["period_to"])}`,
          status,
          actions:
            status === "draft" && can(permissions, "payroll_export.export") ? (
              <RefreshPayrollRunButton runId={id} />
            ) : null,
          fields: [
            { label: t("Format"), value: dash(asText(record["format"])) },
            { label: t("Exported"), value: dateTime(record["exported_at"]) },
            { label: t("Checksum"), value: dash(asText(record["checksum"])) },
          ],
          tables: [
            {
              title: t("Lines"),
              headers: [t("Employee"), t("Code"), t("Kind"), t("Quantity")],
              rows: rowsOf(record["lines"]).map((row) => [
                text_(row, "employee_name"),
                text_(row, "code"),
                humanize(text_(row, "kind")),
                `${text_(row, "quantity")} ${text_(row, "unit")}`.trim(),
              ]),
              empty: t("The run has no lines yet."),
            },
          ],
        };
      }
      case "legal-entities": {
        const archived = record["archived_at"] !== null;

        return {
          title: text("name"),
          description: text("code"),
          status: archived ? "archived" : "active",
          actions: can(permissions, "legal_entities.manage") ? (
            <LegalEntityActions
              entityId={id}
              isDefault={record["is_default"] === true}
              archived={archived}
            />
          ) : null,
          fields: [
            { label: t("VAT number"), value: dash(asText(record["vat_number"])) },
            { label: t("Chamber of Commerce"), value: dash(asText(record["coc_number"])) },
            { label: t("IBAN"), value: dash(asText(record["iban"])) },
            { label: t("Currency"), value: dash(asText(record["default_currency"])) },
            { label: t("Default"), value: yesNo(record["is_default"]) },
          ],
          tables: [],
        };
      }
      case "funding": {
        const status = text("status");

        return {
          title: text("reference") || t("Funding award"),
          description: `${text("subject_type")} ${text("subject_id")}`.trim(),
          status,
          actions: can(permissions, "funding.write") ? (
            <FundingActions awardId={id} status={status} />
          ) : null,
          fields: [
            { label: t("Units"), value: text("units") },
            { label: t("Period"), value: humanize(text("period")) },
            { label: t("Starts"), value: date(record["starts_on"]) },
            { label: t("Ends"), value: date(record["ends_on"]) },
          ],
          tables: [
            {
              title: t("Deliveries"),
              headers: [t("Date"), t("Units"), t("Status")],
              rows: rowsOf(record["deliveries"]).map((row) => [
                date(row["delivered_on"]),
                text_(row, "units"),
                statusText(text_(row, "status")),
              ]),
              empty: t("Nothing was delivered against this award."),
            },
          ],
        };
      }
      case "bank-accounts": {
        return {
          title: text("name"),
          description: dash(asText(record["iban"])),
          status: record["archived_at"] ? "archived" : "active",
          fields: [
            { label: t("Holder"), value: dash(asText(record["holder"])) },
            { label: t("Currency"), value: currency },
            { label: t("BIC"), value: dash(asText(record["bic"])) },
            { label: t("Primary"), value: yesNo(record["is_primary"]) },
          ],
          tables: [
            {
              title: t("Latest transactions"),
              headers: [t("Booked"), t("Counterparty"), t("Amount"), t("Status")],
              rows: rowsOf(record["transactions"]).map((row) => [
                date(row["bookedOn"]),
                text_(row, "counterparty"),
                money(row["amount"], row["currency"]),
                statusText(text_(row, "status")),
              ]),
              empty: t("No transactions were imported."),
            },
          ],
        };
      }
      case "bank-transactions": {
        return {
          title: text("counterparty_name") || t("Bank transaction"),
          description: text("account"),
          status: text("status"),
          fields: [
            { label: t("Booked"), value: date(record["booked_on"]) },
            { label: t("Amount"), value: money(record["amount"], currency) },
            { label: t("Counterparty IBAN"), value: dash(asText(record["counterparty_iban"])) },
            { label: t("Remittance"), value: dash(asText(record["remittance"])) },
          ],
          tables: [
            {
              title: t("Matches"),
              headers: [t("Matched to"), t("Amount"), t("Date")],
              rows: rowsOf(record["matches"]).map((row) => [
                `${humanize(text_(row, "target_type"))} ${text_(row, "target_id").slice(0, 8)}`,
                money(row["amount"], currency),
                dateTime(row["created_at"]),
              ]),
              empty: t("Not matched to an invoice or an entry."),
            },
          ],
        };
      }
      default: {
        const unknown: never = entity;

        return unknown;
      }
    }
  })();

  return (
    <RecordDetailFrame
      title={view.title}
      {...(view.description ? { description: view.description } : {})}
      status={
        view.status ? (
          <Badge variant={statusVariant(view.status)}>
            {statusText(view.status)}
          </Badge>
        ) : null
      }
      actions={view.actions}
    >
      <Card>
        <CardHeader>
          <CardTitle>{t("Details")}</CardTitle>
        </CardHeader>
        <CardContent>
          <dl className="grid gap-4 sm:grid-cols-2">
            {view.fields.map((field) => (
              <div key={field.label} className="flex flex-col gap-1">
                <dt className="text-xs text-muted-foreground">{field.label}</dt>
                <dd className="text-sm">{field.value}</dd>
              </div>
            ))}
          </dl>
        </CardContent>
      </Card>
      {view.tables.map((table) => (
        <Card key={table.title}>
          <CardHeader>
            <CardTitle>{table.title}</CardTitle>
            {table.rows.length === 0 ? (
              <CardDescription>{table.empty}</CardDescription>
            ) : null}
          </CardHeader>
          {table.rows.length > 0 ? (
            <CardContent>
              <Table>
                <TableHeader>
                  <TableRow>
                    {table.headers.map((header) => (
                      <TableHead key={header}>{header}</TableHead>
                    ))}
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {table.rows.map((row, index) => (
                    <TableRow key={index}>
                      {row.map((cell, column) => (
                        <TableCell key={column}>{cell}</TableCell>
                      ))}
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          ) : null}
        </Card>
      ))}
    </RecordDetailFrame>
  );
}

/** A record's text field, empty when it holds none. */
function text_(row: Json, key: string): string {
  return asText(row[key]) ?? "";
}

export function FinanceDetailSkeleton() {
  return (
    <div className="grid items-start gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-6 lg:col-span-2">
        <Skeleton className="h-10 w-72" />
        <Skeleton className="h-48 w-full" />
        <Skeleton className="h-40 w-full" />
      </div>
    </div>
  );
}
