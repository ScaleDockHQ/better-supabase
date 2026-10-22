import { HistoryIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";

import { Badge } from "@/components/reui/badge";
import { buttonVariants } from "@/components/ui/button";
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

import type { Loaded, TimelineRow } from "../customer-record-queries";

import { RecordCardSkeleton, RecordLoadError } from "./record-card-states";

// #region recipe:subject-timeline
/**
 * The customer's history from `customerRecord.timeline`: comments, files and
 * versions in one list, newest first.
 */
export async function CustomerTimeline({
  timeline,
  authors,
}: {
  timeline: Loaded<readonly TimelineRow[]>;
  authors: Readonly<Record<string, string>>;
}) {
  const [t, format] = await Promise.all([
    getExtracted("customers"),
    getFormatter(),
  ]);

  const kindLabel = (kind: string): string => {
    switch (kind) {
      case "comment": {
        return t("Comment");
      }

      case "attachment": {
        return t("File");
      }

      case "version": {
        return t("Version");
      }

      default: {
        return kind;
      }
    }
  };

  return (
    <Card size="sm" data-recipe="record-timeline">
      <CardHeader>
        <CardTitle>{t("Timeline")}</CardTitle>
        <CardDescription>
          {t("Comments, files and versions, newest first.")}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {timeline.kind === "error" ? (
          <RecordLoadError title={t("The timeline didn't load")} />
        ) : timeline.data.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <HistoryIcon />
              </EmptyMedia>
              <EmptyTitle>{t("Nothing happened yet")}</EmptyTitle>
              <EmptyDescription>
                {t("Comments, files and versions show up here.")}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <a
                href="#comments"
                className={buttonVariants({ variant: "outline", size: "sm" })}
              >
                {t("Write a comment")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <ol className="flex flex-col gap-3">
            {timeline.data.map((entry) => (
              <li key={entry.id} className="flex items-center gap-2 text-sm">
                <Badge variant="outline">{kindLabel(entry.kind)}</Badge>
                <span className="truncate">
                  {(entry.actor === null ? undefined : authors[entry.actor]) ??
                    t("Someone")}
                </span>
                <time
                  dateTime={new Date(entry.at).toISOString()}
                  className="ml-auto shrink-0 text-xs text-muted-foreground tabular-nums"
                >
                  {format.relativeTime(entry.at)}
                </time>
              </li>
            ))}
          </ol>
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:subject-timeline

export function CustomerTimelineSkeleton() {
  return <RecordCardSkeleton rows={4} />;
}
