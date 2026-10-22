// #region recipe:subject-link
"use client";

import type { RecordRef } from "better-supabase/blocks/subjects";

import { useSubject } from "better-supabase/blocks/subjects/react";
import { RotateCwIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Link } from "@/i18n/navigation";

/**
 * A link to any subject in `config.records`, titled and routed by
 * `subject_titles`. The links rendered in one pass share one round trip, and a
 * subject the caller can't read shows as plain text.
 */
export function SubjectLink({ subject }: { subject: RecordRef }) {
  const t = useExtracted("subjects");
  const { subject: resolved, error, refresh } = useSubject(subject);

  if (error) {
    return (
      <span className="flex items-center gap-1 text-sm text-muted-foreground">
        {t("The title didn't load")}
        <Button
          size="icon-xs"
          variant="ghost"
          aria-label={t("Retry")}
          onClick={() => {
            void refresh();
          }}
        >
          <RotateCwIcon />
        </Button>
      </span>
    );
  }

  if (resolved === undefined) {
    return <Skeleton className="h-4 w-32" />;
  }

  if (resolved === null) {
    return (
      <span className="truncate text-sm text-muted-foreground">
        {t("A record you can't open")}
      </span>
    );
  }

  const title = resolved.title ?? t("Untitled");

  return resolved.url === undefined ? (
    <span className="truncate text-sm font-medium">{title}</span>
  ) : (
    <Link
      href={resolved.url}
      className="truncate text-sm font-medium underline-offset-4 transition-colors hover:underline"
    >
      {title}
    </Link>
  );
}
// #endregion recipe:subject-link
