import { SearchIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import {
  Item,
  ItemActions,
  ItemContent,
  ItemDescription,
  ItemGroup,
  ItemTitle,
} from "@/components/ui/item";
import { Skeleton } from "@/components/ui/skeleton";
import { Link, toAppHref } from "@/i18n/navigation";

import { searchRecords, SEARCH_PAGE_SIZE } from "../search-queries";
import { SubjectTypeLabel } from "../use-subject-type-label";

const facetHref = (q: string, type: string | undefined) =>
  toAppHref(
    `/search?q=${encodeURIComponent(q)}${type === undefined ? "" : `&type=${encodeURIComponent(type)}`}`,
  );

/**
 * The matches of `q` as rows, with a facet per subject type. Render inside
 * `<Suspense>`; the fallback is `SearchResultsSkeleton`.
 */
export async function SearchResults({
  q,
  type,
}: {
  q: string;
  type: string | undefined;
}) {
  const [t, data] = await Promise.all([
    getExtracted("search"),
    searchRecords(q, type),
  ]);

  if (q.trim() === "") {
    return (
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <SearchIcon />
          </EmptyMedia>
          <EmptyTitle>{t("Search every record")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Type a name, a number or a few words. Results cover every record you can read, grouped by type.",
            )}
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  if (data.facets.length === 0) {
    return (
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <SearchIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No records match {q}", { q })}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Check the spelling, or search with fewer words. Records you cannot read never appear.",
            )}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <Button variant="outline" render={<Link href="/assistant" />}>
            {t("Ask the assistant")}
          </Button>
        </EmptyContent>
      </Empty>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <nav aria-label={t("Filter by type")} className="flex flex-wrap gap-2">
        <Button
          size="sm"
          variant={type === undefined ? "default" : "outline"}
          render={<Link href={facetHref(q, undefined)} />}
        >
          {t("All")}
        </Button>
        {data.facets.map((facet) => (
          <Button
            key={facet.type}
            size="sm"
            variant={type === facet.type ? "default" : "outline"}
            render={<Link href={facetHref(q, facet.type)} />}
          >
            <SubjectTypeLabel type={facet.type} />
            <span className="text-xs opacity-70">
              {data.capped ? `${String(facet.count)}+` : facet.count}
            </span>
          </Button>
        ))}
      </nav>
      <ItemGroup>
        {data.rows.map((row) => (
          <Item
            key={`${row.subjectType}:${row.subjectId}`}
            variant="outline"
            size="sm"
            render={
              row.url === null ? undefined : <Link href={toAppHref(row.url)} />
            }
          >
            <ItemContent>
              <ItemTitle>{row.title ?? row.subjectId}</ItemTitle>
              {row.snippet === null ? null : (
                <ItemDescription>{row.snippet}</ItemDescription>
              )}
            </ItemContent>
            <ItemActions>
              <Badge variant="outline">
                <SubjectTypeLabel type={row.subjectType} />
              </Badge>
            </ItemActions>
          </Item>
        ))}
      </ItemGroup>
      {data.rows.length >= SEARCH_PAGE_SIZE ? (
        <p className="text-sm text-muted-foreground">
          {t(
            "Showing the best {count, number} matches. Narrow the search to see others.",
            { count: SEARCH_PAGE_SIZE },
          )}
        </p>
      ) : null}
    </div>
  );
}

export function SearchResultsSkeleton() {
  return (
    <div className="flex flex-col gap-4" aria-busy="true">
      <div className="flex gap-2">
        <Skeleton className="h-8 w-14" />
        <Skeleton className="h-8 w-24" />
        <Skeleton className="h-8 w-20" />
      </div>
      <div className="flex flex-col gap-2">
        {Array.from({ length: 6 }, (_, index) => (
          <Skeleton key={index} className="h-14 w-full" />
        ))}
      </div>
    </div>
  );
}
