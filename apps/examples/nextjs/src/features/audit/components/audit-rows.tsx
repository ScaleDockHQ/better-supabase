import { getExtracted, getFormatter } from "next-intl/server";

import { buttonVariants } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Link } from "@/i18n/navigation";

import type { AuditFilters } from "../audit-queries";

import { getAuditEntry, getAuditPage, getAuditTotal } from "../audit-queries";
import { AuditEntrySheet } from "./audit-entry-sheet";

/** A link to the page with some of the filters changed. */
function hrefOf(
  filters: AuditFilters,
  change: Partial<Record<keyof AuditFilters, string | null>>,
) {
  const next = { ...filters, ...change };
  const query: Record<string, string> = {};

  for (const key of [
    "actor",
    "type",
    "from",
    "to",
    "q",
    "before",
    "entry",
  ] as const) {
    const value = next[key];

    if (value) {
      query[key] = value;
    }
  }

  return { pathname: "/settings/audit", query } as const;
}

/**
 * 50 summary rows, with Older and back to newest as links, so the DOM stays
 * small.
 */
export async function AuditRows({
  organizationId,
  filters,
}: {
  organizationId: string;
  filters: AuditFilters;
}) {
  const [t, format, page] = await Promise.all([
    getExtracted("audit"),
    getFormatter(),
    getAuditPage(organizationId, filters),
  ]);

  const filtered =
    filters.actor !== null || filters.type !== null || filters.q !== "";

  if (page.entries.length === 0) {
    return (
      <div className="grid justify-items-start gap-2">
        <p className="text-sm text-muted-foreground">
          {filtered
            ? t("Nothing matches these filters.")
            : t("Nothing recorded yet.")}
        </p>
        {filtered ? (
          <Link
            href="/settings/audit"
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            {t("Clear filters")}
          </Link>
        ) : null}
      </div>
    );
  }

  return (
    <div className="grid gap-4">
      <Table data-testid="audit-events">
        <TableHeader>
          <TableRow>
            <TableHead>{t("When")}</TableHead>
            <TableHead>{t("Event")}</TableHead>
            <TableHead className="hidden md:table-cell">{t("Actor")}</TableHead>
            <TableHead className="hidden md:table-cell">
              {t("Target")}
            </TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {page.entries.map((entry) => (
            <TableRow key={entry.id}>
              <TableCell className="whitespace-nowrap text-muted-foreground tabular-nums">
                {format.dateTime(new Date(entry.occurredAt.epochMilliseconds), {
                  dateStyle: "short",
                  timeStyle: "short",
                })}
              </TableCell>
              <TableCell className="font-mono text-xs">
                <Link
                  href={hrefOf(filters, { entry: entry.id })}
                  prefetch={false}
                  className="hover:underline"
                >
                  {entry.eventType ??
                    `${entry.op ?? "change"} ${entry.table ?? ""}`.trim()}
                </Link>
              </TableCell>
              <TableCell className="hidden max-w-48 truncate md:table-cell">
                {entry.actorLabel ?? entry.actorId ?? "–"}
              </TableCell>
              <TableCell className="hidden max-w-48 truncate md:table-cell">
                {entry.targetLabel ?? entry.record ?? "–"}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
      <div className="flex items-center justify-between gap-2">
        {filters.before ? (
          <Link
            href={hrefOf(filters, { before: null, entry: null })}
            prefetch={false}
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            {t("Newest")}
          </Link>
        ) : (
          <span />
        )}
        {page.next ? (
          <Link
            href={hrefOf(filters, { before: page.next, entry: null })}
            prefetch={false}
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            {t("Older")}
          </Link>
        ) : null}
      </div>
      <AuditEntrySheet>
        {filters.entry ? <AuditEntryDetails entryId={filters.entry} /> : null}
      </AuditEntrySheet>
    </div>
  );
}

async function AuditEntryDetails({ entryId }: { entryId: string }) {
  const [t, entry] = await Promise.all([
    getExtracted("audit"),
    getAuditEntry(entryId),
  ]);

  if (!entry) {
    return <p className="text-sm text-muted-foreground">{t("Not found.")}</p>;
  }

  return (
    <dl className="grid gap-3 text-sm">
      <div>
        <dt className="text-xs text-muted-foreground">{t("Event")}</dt>
        <dd className="font-mono">{entry.eventType ?? entry.op}</dd>
      </div>
      <div>
        <dt className="text-xs text-muted-foreground">{t("Summary")}</dt>
        <dd>{entry.summary ?? "–"}</dd>
      </div>
      {entry.old ? (
        <div>
          <dt className="text-xs text-muted-foreground">{t("Before")}</dt>
          <dd>
            <pre className="overflow-x-auto rounded-md bg-muted p-2 text-xs">
              {JSON.stringify(entry.old, null, 2)}
            </pre>
          </dd>
        </div>
      ) : null}
      {entry.new ? (
        <div>
          <dt className="text-xs text-muted-foreground">{t("After")}</dt>
          <dd>
            <pre className="overflow-x-auto rounded-md bg-muted p-2 text-xs">
              {JSON.stringify(entry.new, null, 2)}
            </pre>
          </dd>
        </div>
      ) : null}
    </dl>
  );
}

/**
 * The matches, up to the cap, under its own boundary so a slow count never
 * holds the rows.
 */
export async function AuditTotal({
  organizationId,
  filters,
}: {
  organizationId: string;
  filters: AuditFilters;
}) {
  const [t, total] = await Promise.all([
    getExtracted("audit"),
    getAuditTotal(organizationId, filters),
  ]);

  return (
    <p className="text-xs text-muted-foreground" data-testid="audit-total">
      {total >= 10_000
        ? t("10,000 or more entries")
        : t("{count, number} entries", { count: total })}
    </p>
  );
}

export function AuditTotalSkeleton() {
  return <Skeleton className="h-4 w-28" aria-busy="true" />;
}

export function AuditRowsSkeleton() {
  return <Skeleton className="h-64" aria-busy="true" />;
}
