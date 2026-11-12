import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  SearchForm,
  SearchFormSkeleton,
} from "@/features/search/components/search-form";
import {
  SearchResults,
  SearchResultsSkeleton,
} from "@/features/search/components/search-results";
import { SemanticSearchNote } from "@/features/search/components/semantic-search-note";
import { PermissionGate } from "@/features/user/components/permission-gate";

// A prefetch holds the header and the query box; the rows render on navigation.
export const ensureStatic = "prefetch";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/loading-sequences.spec.ts checks it in a build.
export const instant = true;

const first = (value: string | string[] | undefined): string | undefined =>
  Array.isArray(value) ? value[0] : value;

export default function SearchPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("search");

  return (
    <>
      <PageHeader
        title={t("Search")}
        description={t(
          "One search over every record you can read, answered by the database.",
        )}
      />
      <Suspense fallback={<SearchFormSkeleton />}>
        <SearchForm />
      </Suspense>
      <Suspense fallback={<SearchResultsSkeleton />}>
        <PermissionGate permission="search.read">
          {searchParams.then((query) => (
            <SearchResults
              q={first(query["q"]) ?? ""}
              type={first(query["type"])}
            />
          ))}
        </PermissionGate>
      </Suspense>
      <SemanticSearchNote />
    </>
  );
}
