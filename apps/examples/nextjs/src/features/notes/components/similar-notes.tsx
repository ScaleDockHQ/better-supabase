import { getExtracted } from "next-intl/server";

import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

import { getSimilarNotes } from "../note-queries";

/** Render inside `<Suspense>`: vector search over the organization's notes. */
export async function SimilarNotes() {
  const [result, t] = await Promise.all([
    getSimilarNotes(),
    getExtracted("notes"),
  ]);
  if (!result) return null;
  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Similar notes")}</CardTitle>
        <CardDescription>
          {t("Nearest to “{body}”, found by the vector-search module.", {
            body: result.source.body,
          })}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ol className="divide-y" data-testid="similar-notes">
          {result.similar.map((note) => (
            <li
              key={note.id}
              className="flex items-center justify-between gap-3 py-2 text-sm"
            >
              <span>{note.body}</span>
              <Badge variant="outline">{note.kind}</Badge>
            </li>
          ))}
        </ol>
      </CardContent>
    </Card>
  );
}

export function SimilarNotesSkeleton() {
  return <Skeleton className="h-48 rounded-xl" aria-busy="true" />;
}
