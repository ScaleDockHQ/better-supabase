import { MailIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";

import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
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

import { getOpenInvitations } from "../organization-invitations";

/**
 * The open invitations the `organizations` block lists through
 * `invitationsPage`.
 */
export async function InvitationsOverview() {
  const [t, format, invitations] = await Promise.all([
    getExtracted("organization"),
    getFormatter(),
    getOpenInvitations().catch(() => null),
  ]);

  if (invitations === null) {
    return (
      <Alert variant="destructive">
        <AlertTitle>{t("The invitations didn't load")}</AlertTitle>
        <AlertDescription>
          <Link href="/members/invitations" className="underline">
            {t("Try again")}
          </Link>
        </AlertDescription>
      </Alert>
    );
  }

  if (invitations.length === 0) {
    return (
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <MailIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No open invitations")}</EmptyTitle>
          <EmptyDescription>
            {t("Invite people from the members page.")}
          </EmptyDescription>
        </EmptyHeader>
        <Link href="/settings/members" className="text-sm underline">
          {t("Open members")}
        </Link>
      </Empty>
    );
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{t("Email")}</TableHead>
          <TableHead>{t("Role")}</TableHead>
          <TableHead>{t("Expires")}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {invitations.map((invitation) => (
          <TableRow key={invitation.id}>
            <TableCell className="font-medium">{invitation.email}</TableCell>
            <TableCell>{invitation.role}</TableCell>
            <TableCell className="tabular-nums">
              {invitation.expiresAt === null
                ? "–"
                : format.dateTime(new Date(invitation.expiresAt), {
                    dateStyle: "medium",
                    timeZone: "UTC",
                  })}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

export function InvitationsOverviewSkeleton() {
  return (
    <div aria-busy="true" className="flex flex-col gap-2">
      <Skeleton className="h-8" />
      <Skeleton className="h-8" />
      <Skeleton className="h-8" />
    </div>
  );
}
