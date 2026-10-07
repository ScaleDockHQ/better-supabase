import { hasEntitlement } from "better-supabase/blocks/entitlements";
import { DownloadIcon, ScrollTextIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";

import { buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
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
import { activeOrganizationId } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { Link } from "@/i18n/navigation";

import { getAuditEvents } from "../audit-queries";

/** Render inside `<Suspense>`. The log is a plan feature (`audit`). */
export async function AuditLog() {
  const session = await getSession();
  const organizationId = activeOrganizationId(session);
  if (!organizationId) return null;
  const t = await getExtracted("audit");
  if (!hasEntitlement(session, organizationId, "audit")) {
    return (
      <Empty className="border" data-testid="audit-upsell">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <ScrollTextIcon />
          </EmptyMedia>
          <EmptyTitle>{t("The audit log is on the Pro plan")}</EmptyTitle>
          <EmptyDescription>
            {t("Upgrade to see who changed what, and to export it.")}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <Link href="/settings/billing" className={buttonVariants()}>
            {t("See plans")}
          </Link>
        </EmptyContent>
      </Empty>
    );
  }
  const [events, format] = await Promise.all([
    getAuditEvents(organizationId),
    getFormatter(),
  ]);
  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Audit log")}</CardTitle>
        <CardDescription>
          {t("Database changes and app events, recorded by the audit module.")}
        </CardDescription>
        <CardAction>
          <a
            href="/api/audit/export"
            download
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            <DownloadIcon />
            {t("Export CSV")}
          </a>
        </CardAction>
      </CardHeader>
      <CardContent>
        {events.length === 0 ? (
          <p className="text-muted-foreground text-sm">
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
              {events.map((event) => (
                <TableRow key={event.id}>
                  <TableCell className="text-muted-foreground whitespace-nowrap tabular-nums">
                    {format.dateTime(new Date(event.occurredAt), {
                      dateStyle: "short",
                      timeStyle: "short",
                    })}
                  </TableCell>
                  <TableCell className="font-mono text-xs">
                    {event.eventType}
                  </TableCell>
                  <TableCell className="hidden max-w-48 truncate md:table-cell">
                    {event.actor ?? "–"}
                  </TableCell>
                  <TableCell className="hidden max-w-48 truncate md:table-cell">
                    {event.target ?? "–"}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}

export function AuditLogSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}
