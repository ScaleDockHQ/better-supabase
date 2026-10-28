import { DatabaseIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";

import type { AppHref } from "@/i18n/navigation";

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
import { Skeleton } from "@/components/ui/skeleton";
import { Link } from "@/i18n/navigation";

import type { Islands, IslandScope, IslandTable } from "../islands-queries";

import { getIslandsIn } from "../islands-queries";
import { IslandError } from "./island-error";

/** Where a user adds the first row of each table. */
const ADD_HREF: Record<IslandTable, AppHref> = {
  customers: "/customers",
  notes: "/customers",
  contacts: "/customers",
  tags: "/customers",
  tasks: "/work",
};

/**
 * Render inside `<Suspense>`: one table's row count. Every island reads the
 * same bootstrap result, so the ten of them cost one query.
 */
export async function CountIsland({
  table,
  scope,
}: {
  table: IslandTable;
  scope: Promise<IslandScope>;
}) {
  const [t, format] = await Promise.all([
    getExtracted("islands"),
    getFormatter(),
  ]);

  const titles: Record<IslandTable, string> = {
    customers: t("Customers"),
    notes: t("Notes"),
    contacts: t("Contacts"),
    tags: t("Tags"),
    tasks: t("Tasks"),
  };

  const title = titles[table];
  let islands: Islands;

  try {
    islands = await getIslandsIn(await scope);
  } catch {
    return <IslandError title={title} />;
  }

  const count = islands.counts?.[table];

  if (count === undefined) {
    return null;
  }

  return (
    <Card data-testid={`island-${table}`}>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{t("Rows in this organization")}</CardDescription>
      </CardHeader>
      <CardContent>
        {count === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <DatabaseIcon aria-hidden />
              </EmptyMedia>
              <EmptyTitle>{t("Nothing here yet")}</EmptyTitle>
              <EmptyDescription>
                {islands.canWrite
                  ? t("Add the first row to see it counted.")
                  : t("An admin adds the first row.")}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Link
                href={ADD_HREF[table]}
                className={buttonVariants({ variant: "outline", size: "sm" })}
              >
                {islands.canWrite ? t("Add one") : t("Open")}
              </Link>
            </EmptyContent>
          </Empty>
        ) : (
          <span className="text-3xl font-semibold tabular-nums">
            {format.number(count)}
          </span>
        )}
      </CardContent>
    </Card>
  );
}

export function CountIslandSkeleton() {
  return <Skeleton className="h-36 rounded-xl" aria-busy="true" />;
}
