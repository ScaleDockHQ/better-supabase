import { getExtracted, getFormatter } from "next-intl/server";

import { Button, buttonVariants } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Link } from "@/i18n/navigation";

import type { Islands, IslandScope } from "../islands-queries";

import { evictMyIslands } from "../islands-actions";
import { getIslandsIn } from "../islands-queries";

/**
 * Render inside `<Suspense>`: the cache scope switch, when the shown entry was
 * computed, and a button that evicts the caller's entries in both scopes.
 */
export async function CacheStatus({ scope }: { scope: Promise<IslandScope> }) {
  const [current, t, format] = await Promise.all([
    scope,
    getExtracted("islands"),
    getFormatter(),
  ]);

  let islands: Islands | null;

  try {
    islands = await getIslandsIn(current);
  } catch {
    // Each island shows its own error with a Retry.
    islands = null;
  }

  const tab = (active: boolean) =>
    buttonVariants({ variant: active ? "secondary" : "ghost", size: "sm" });

  return (
    <div className="flex flex-wrap items-center gap-2">
      <nav aria-label={t("Cache scope")} className="flex items-center gap-1">
        <Link
          href="/islands"
          aria-current={current === "private" ? "page" : undefined}
          className={tab(current === "private")}
        >
          {t("Private")}
        </Link>
        <Link
          href="/islands?scope=remote"
          aria-current={current === "remote" ? "page" : undefined}
          className={tab(current === "remote")}
        >
          {t("Remote")}
        </Link>
      </nav>
      {islands ? (
        <span className="flex items-center gap-1 text-xs text-muted-foreground">
          {t("Computed at")}
          <time
            dateTime={islands.cachedAt}
            className="tabular-nums"
            data-testid="islands-cached-at"
          >
            {format.dateTime(new Date(islands.cachedAt), {
              timeStyle: "medium",
            })}
          </time>
        </span>
      ) : null}
      <form action={evictMyIslands}>
        <Button size="sm" variant="outline" type="submit">
          {t("Evict my cached views")}
        </Button>
      </form>
    </div>
  );
}

export function CacheStatusSkeleton() {
  return <Skeleton className="h-8 w-80" aria-busy="true" />;
}
