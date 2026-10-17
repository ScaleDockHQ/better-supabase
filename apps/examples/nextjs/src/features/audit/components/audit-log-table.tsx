// #region recipe:audit-log-table
"use client";

import { useAuditLog } from "better-supabase/blocks/audit/react";
import { useExtracted, useFormatter } from "next-intl";

import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { useErrorMessage } from "@/lib/use-error-message";

const ALL = "all";

/** The values a filter offers: those on the loaded page, and the one it has. */
function choices(
  values: readonly (string | undefined)[],
  current: string | undefined,
): readonly string[] {
  return [
    ...new Set([...values, current].filter((value) => value !== undefined)),
  ].toSorted();
}

/**
 * The organization's audit trail through the browser client, newest first,
 * filtered by actor and action. The audit module's read policy decides
 * which entries the caller sees.
 */
export function AuditLogTable({ organizationId }: { organizationId: string }) {
  const t = useExtracted("audit");
  const format = useFormatter();
  const errorMessage = useErrorMessage();

  const { entries, filters, hasMore, loading, error, setFilters, loadMore } =
    useAuditLog({ organizationId, schema: blockConfig.audit.api });

  const actors = new Map(
    (entries ?? []).flatMap((entry) =>
      entry.actorId ? [[entry.actorId, entry.actorLabel ?? entry.actorId]] : [],
    ),
  );

  const actions = choices(
    (entries ?? []).map((entry) => entry.eventType),
    filters.eventType,
  );

  const actorItems = [
    { value: ALL, label: t("Every actor") },
    ...choices([...actors.keys()], filters.actorId).map((id) => ({
      value: id,
      label: actors.get(id) ?? id,
    })),
  ];

  const actionItems = [
    { value: ALL, label: t("Every action") },
    ...actions.map((action) => ({ value: action, label: action })),
  ];

  const pick = (value: string | null): string | undefined =>
    value === null || value === ALL ? undefined : value;

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap gap-2">
        <Select
          value={filters.actorId ?? ALL}
          items={actorItems}
          onValueChange={(value) => {
            void setFilters({ ...filters, actorId: pick(value) });
          }}
        >
          <SelectTrigger size="sm" className="w-48" aria-label={t("Actor")}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {actorItems.map((item) => (
              <SelectItem key={item.value} value={item.value}>
                {item.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Select
          value={filters.eventType ?? ALL}
          items={actionItems}
          onValueChange={(value) => {
            void setFilters({ ...filters, eventType: pick(value) });
          }}
        >
          <SelectTrigger size="sm" className="w-56" aria-label={t("Action")}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {actionItems.map((item) => (
              <SelectItem key={item.value} value={item.value}>
                {item.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      {error ? (
        <p className="text-sm text-destructive">{errorMessage(error)}</p>
      ) : null}
      {entries === undefined ? (
        <Skeleton className="h-64" />
      ) : entries.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          {t("Nothing recorded yet.")}
        </p>
      ) : (
        <Table data-testid="audit-events">
          <TableHeader>
            <TableRow>
              <TableHead>{t("When")}</TableHead>
              <TableHead>{t("Event")}</TableHead>
              <TableHead className="hidden md:table-cell">
                {t("Actor")}
              </TableHead>
              <TableHead className="hidden md:table-cell">
                {t("Target")}
              </TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {entries.map((entry) => (
              <TableRow key={entry.id}>
                <TableCell className="whitespace-nowrap text-muted-foreground tabular-nums">
                  {format.dateTime(
                    new Date(entry.occurredAt.epochMilliseconds),
                    { dateStyle: "short", timeStyle: "short" },
                  )}
                </TableCell>
                <TableCell className="font-mono text-xs">
                  {entry.eventType ??
                    `${entry.op ?? "change"} ${entry.table ?? ""}`.trim()}
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
      )}
      {hasMore ? (
        <Button
          variant="outline"
          size="sm"
          className="justify-self-center"
          disabled={loading}
          onClick={() => {
            void loadMore();
          }}
        >
          {t("Load more")}
        </Button>
      ) : null}
    </div>
  );
}
// #endregion recipe:audit-log-table
