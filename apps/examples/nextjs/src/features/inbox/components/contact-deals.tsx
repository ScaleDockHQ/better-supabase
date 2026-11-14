"use client";

import { useQuery } from "@tanstack/react-query";
import { useExtracted, useLocale } from "next-intl";

import { Button } from "@/components/ui/button";
import {
  Item,
  ItemContent,
  ItemDescription,
  ItemGroup,
  ItemTitle,
} from "@/components/ui/item";
import { Skeleton } from "@/components/ui/skeleton";
import { Link, toAppHref } from "@/i18n/navigation";

interface Deals {
  readonly deals: readonly {
    readonly id: string;
    readonly name: string;
    readonly amount: string;
    readonly company: string | null;
  }[];
}

/**
 * The open deals that name the conversation's contact. It loads after the
 * thread paints from `/api/inbox/contact-deals`, so the inbox page ships no
 * deals code.
 */
export function ContactDeals({ conversationId }: { conversationId: string }) {
  const t = useExtracted("inbox");
  const locale = useLocale();

  const query = useQuery({
    queryKey: ["inbox-contact-deals", conversationId, locale],
    queryFn: async ({ signal }) => {
      const response = await fetch(
        `/api/inbox/contact-deals?conversation=${encodeURIComponent(conversationId)}&locale=${encodeURIComponent(locale)}`,
        { signal },
      );

      if (!response.ok) {
        throw new Error(`contact deals answered ${response.status}`);
      }

      // SAFETY: `/api/inbox/contact-deals` answers with `{ deals }`.
      return ((await response.json()) as Deals).deals;
    },
    staleTime: 30_000,
  });

  return (
    <section className="flex flex-col gap-2">
      <h2 className="text-sm font-medium">{t("Open deals")}</h2>
      {query.isPending ? <Skeleton className="h-12 w-full" /> : null}
      {query.isError ? (
        <div className="flex flex-col items-start gap-2">
          <p className="text-sm text-muted-foreground">
            {t("The deals didn't load.")}
          </p>
          <Button
            size="sm"
            variant="outline"
            onClick={() => {
              void query.refetch();
            }}
          >
            {t("Retry")}
          </Button>
        </div>
      ) : null}
      {query.data?.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          {t("No open deals name this contact.")}
        </p>
      ) : null}
      {query.data !== undefined && query.data.length > 0 ? (
        <ItemGroup>
          {query.data.map((deal) => (
            <Item
              key={deal.id}
              variant="outline"
              size="sm"
              render={<Link href={toAppHref("/crm/deals")} prefetch={false} />}
            >
              <ItemContent>
                <ItemTitle>{deal.name}</ItemTitle>
                <ItemDescription>{deal.company ?? "-"}</ItemDescription>
              </ItemContent>
              <span className="text-sm tabular-nums">{deal.amount}</span>
            </Item>
          ))}
        </ItemGroup>
      ) : null}
    </section>
  );
}
