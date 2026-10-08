import { getExtracted, getFormatter } from "next-intl/server";

import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { Link } from "@/i18n/navigation";

import { getDefinitions } from "../builder-queries";

/** Render inside `<Suspense>`. */
export async function DefinitionList() {
  const [definitions, t, format] = await Promise.all([
    getDefinitions(),
    getExtracted("workflows"),
    getFormatter(),
  ]);
  if (definitions.length === 0) {
    return (
      <p className="text-muted-foreground text-sm">
        {t("No workflows yet. Members who can edit create one above.")}
      </p>
    );
  }
  return (
    <ul className="divide-y rounded-xl border" data-testid="definition-list">
      {definitions.map((definition) => (
        <li
          key={definition.id}
          className="flex items-center justify-between gap-4 px-4 py-3 text-sm"
        >
          <Link
            href={`/workflows/builder/${definition.id}`}
            className="font-medium"
          >
            {definition.name}
          </Link>
          <span className="flex items-center gap-2">
            {definition.published === null ? null : (
              <Badge>
                {t("v{version}", { version: String(definition.published) })}
              </Badge>
            )}
            {definition.draft ? (
              <Badge variant="outline">{t("Draft")}</Badge>
            ) : null}
            <span className="text-muted-foreground text-xs tabular-nums">
              {format.dateTime(new Date(definition.updatedAt), {
                dateStyle: "medium",
              })}
            </span>
          </span>
        </li>
      ))}
    </ul>
  );
}

export function DefinitionListSkeleton() {
  return (
    <div className="space-y-2" aria-busy="true">
      {Array.from({ length: 3 }, (_, index) => (
        <Skeleton key={index} className="h-11 w-full" />
      ))}
    </div>
  );
}
