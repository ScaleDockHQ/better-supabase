import {
  type LucideIcon,
  CalendarIcon,
  CircleCheckIcon,
  HistoryIcon,
  MailIcon,
  PhoneIcon,
  StickyNoteIcon,
} from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";

import { Badge } from "@/components/reui/badge";
import {
  Card,
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
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import type { ContactKind } from "../crm-queries";

import { loadTimeline, settle } from "../crm-queries";
import { CrmLoadError } from "./crm-load-error";
import { LogActivityForm } from "./log-activity-form";

// #region recipe:activity-timeline
const ICONS = new Map<string, LucideIcon>([
  ["call", PhoneIcon],
  ["email", MailIcon],
  ["meeting", CalendarIcon],
  ["note", StickyNoteIcon],
  ["task", CircleCheckIcon],
]);

/**
 * Render inside `<Suspense>`: the calls, emails, meetings and notes logged
 * on a contact, newest first, with a form to log the next one.
 */
export async function ActivityTimeline({
  subject,
}: {
  subject: { type: ContactKind; id: string };
}) {
  const [session, t, format] = await Promise.all([
    getSession(),
    getExtracted("crm"),
    getFormatter(),
  ]);

  if (!can(session, "engagements.read")) {
    return null;
  }

  const timeline = await settle(() => loadTimeline(subject.type, subject.id));

  if (timeline.kind === "no-organization") {
    return null;
  }

  const canLog = can(session, "engagements.write");

  const types = new Map([
    ["call", t("Call")],
    ["email", t("Email")],
    ["meeting", t("Meeting")],
    ["note", t("Note")],
    ["task", t("Task")],
  ]);

  return (
    <Card data-recipe="activity-timeline">
      <CardHeader>
        <CardTitle>{t("Activity")}</CardTitle>
        <CardDescription>
          {t("Calls, emails and meetings with this contact, newest first.")}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-6">
        {timeline.kind === "error" ? (
          <CrmLoadError title={t("The activity didn't load")} />
        ) : timeline.data.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <HistoryIcon />
              </EmptyMedia>
              <EmptyTitle>{t("Nothing logged yet")}</EmptyTitle>
              <EmptyDescription>
                {t("Log the first call, email, meeting or note.")}
              </EmptyDescription>
            </EmptyHeader>
            {canLog ? (
              <EmptyContent>
                <LogActivityForm subject={subject} />
              </EmptyContent>
            ) : null}
          </Empty>
        ) : (
          <>
            {canLog ? (
              <>
                <LogActivityForm subject={subject} />
                <Separator />
              </>
            ) : null}
            <ol className="flex flex-col gap-4">
              {timeline.data.map((entry) => {
                const Icon = ICONS.get(entry.type) ?? StickyNoteIcon;

                return (
                  <li key={entry.id} className="flex gap-3">
                    <span className="flex size-8 shrink-0 items-center justify-center rounded-full bg-muted text-muted-foreground">
                      <Icon className="size-4" aria-hidden />
                    </span>
                    <div className="flex min-w-0 flex-1 flex-col gap-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="text-sm font-medium">
                          {entry.title}
                        </span>
                        <Badge variant="secondary">
                          {types.get(entry.type) ?? entry.type}
                        </Badge>
                        {entry.overdue ? (
                          <Badge variant="warning-light">{t("Overdue")}</Badge>
                        ) : null}
                      </div>
                      {entry.body ? (
                        <p className="text-sm whitespace-pre-line text-muted-foreground">
                          {entry.body}
                        </p>
                      ) : null}
                      <time
                        dateTime={entry.createdAt}
                        className="text-xs text-muted-foreground"
                      >
                        {format.dateTime(new Date(entry.createdAt), {
                          dateStyle: "medium",
                          timeStyle: "short",
                        })}
                      </time>
                    </div>
                  </li>
                );
              })}
            </ol>
          </>
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:activity-timeline

export function ActivityTimelineSkeleton() {
  return <Skeleton className="h-72 rounded-xl" aria-busy="true" />;
}
