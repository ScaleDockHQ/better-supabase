// #region recipe:subject-chip
"use client";

import type { SubjectRef } from "better-supabase/blocks/subjects";

import { useSubject } from "better-supabase/blocks/subjects/react";
import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { Link } from "@/i18n/navigation";

/**
 * A compact badge for a subject: its type and title, linking to its page. Rows
 * that each render a chip share one `subject_titles` call.
 */
export function SubjectChip({ subject }: { subject: SubjectRef }) {
  const t = useExtracted("subjects");
  const { subject: resolved, error } = useSubject(subject);

  if (resolved === undefined && !error) {
    return <Skeleton className="h-5 w-24" />;
  }

  const label = resolved?.title ?? t("Unavailable");

  const content = (
    <>
      <span className="text-muted-foreground">{subject.type}</span>
      <span className="truncate">{label}</span>
    </>
  );

  return resolved?.url === undefined ? (
    <Badge variant="outline">{content}</Badge>
  ) : (
    <Badge
      variant="outline"
      className="transition-colors hover:bg-accent"
      render={<Link href={resolved.url} />}
    >
      {content}
    </Badge>
  );
}
// #endregion recipe:subject-chip
