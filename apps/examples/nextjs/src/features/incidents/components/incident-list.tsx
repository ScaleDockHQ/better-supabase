import type { IncidentStatus } from "better-supabase/blocks/incidents";

import { SirenIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
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

import { getIncidents } from "../incidents-queries";
import { SEVERITY_VARIANT, STATUS_VARIANT } from "./incident-labels";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** Render inside `<Suspense>`: the newest incidents, open ones first. */
export async function IncidentList() {
  const [rows, t, format] = await Promise.all([
    getIncidents().then(
      (data) => ({ ok: true as const, data }),
      () => ({ ok: false as const }),
    ),
    getExtracted("incidents"),
    getFormatter(),
  ]);

  if (!rows.ok) {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The incidents didn't load")}</AlertTitle>
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

  if (rows.data === null) {
    return null;
  }

  if (rows.data.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <SirenIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No incidents")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Open an incident when something breaks. Its timeline, affected components and postmortem live here.",
            )}
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  const open = rows.data.toSorted(
    (a, b) =>
      Number(a.status === "resolved") - Number(b.status === "resolved") ||
      b.startedAt.localeCompare(a.startedAt),
  );

  const statusLabels: Record<IncidentStatus, string> = {
    investigating: t("Investigating"),
    identified: t("Identified"),
    monitoring: t("Monitoring"),
    resolved: t("Resolved"),
  };

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{t("Incident")}</TableHead>
          <TableHead>{t("Severity")}</TableHead>
          <TableHead>{t("Status")}</TableHead>
          <TableHead>{t("Started")}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {open.map((row) => (
          <TableRow key={row.id}>
            <TableCell className="font-medium">
              <Link href={`/incidents/${row.id}`} className="hover:underline">
                {row.title}
              </Link>
            </TableCell>
            <TableCell>
              <Badge variant={SEVERITY_VARIANT[row.severity]}>
                {row.severity.toUpperCase()}
              </Badge>
            </TableCell>
            <TableCell>
              <Badge variant={STATUS_VARIANT[row.status]}>
                {statusLabels[row.status]}
              </Badge>
            </TableCell>
            <TableCell className="text-xs text-muted-foreground">
              {format.dateTime(new Date(row.startedAt), {
                dateStyle: "medium",
                timeStyle: "short",
              })}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

export function IncidentListSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
