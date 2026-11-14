"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { RotateCwIcon, WebhookIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useState } from "react";

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
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/lib/toast";

import type { InboundEventRow } from "../inbox-types";

import { loadInboundEvents, replayInboundEvent } from "../inbox-actions";

const variantOf = (
  status: InboundEventRow["status"],
): "success-light" | "destructive-light" | "info-light" | "secondary" => {
  switch (status) {
    case "processed": {
      return "success-light";
    }

    case "failed": {
      return "destructive-light";
    }

    case "received":
    case "processing": {
      return "info-light";
    }

    case "ignored": {
      return "secondary";
    }

    default: {
      const never: never = status;

      return never;
    }
  }
};

/**
 * The webhook events the channels stored, newest first, with a replay for each:
 * the event is offered again and the next sweep runs it through the handler.
 */
export function InboundEventsSheet() {
  const t = useExtracted("inbox");
  const format = useFormatter();
  const errorMessage = useErrorMessage();
  const [pendingId, setPendingId] = useState<string | null>(null);

  const events = useAction(loadInboundEvents, {
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const replay = useAction(replayInboundEvent, {
    onSuccess: () => {
      setPendingId(null);
      toast.success(t("Queued for replay"));
      void events.run(undefined);
    },
    onError: (error) => {
      setPendingId(null);
      toast.error(errorMessage(error));
    },
  });

  const rows = events.data;

  return (
    <Sheet
      onOpenChange={(next) => {
        if (next) {
          void events.run(undefined);
        }
      }}
    >
      <SheetTrigger
        render={
          <Button variant="outline" size="sm">
            <WebhookIcon />
            {t("Webhook events")}
          </Button>
        }
      />
      <SheetContent className="flex flex-col gap-4">
        <SheetHeader>
          <SheetTitle>{t("Webhook events")}</SheetTitle>
          <SheetDescription>
            {t(
              "What the channels sent, newest first. Replay offers an event to the handler again.",
            )}
          </SheetDescription>
        </SheetHeader>
        <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 pb-4">
          {rows === undefined && events.error === undefined ? (
            <div className="flex flex-col gap-2" aria-busy="true">
              {Array.from({ length: 4 }, (_, index) => (
                <Skeleton key={index} className="h-14 w-full" />
              ))}
            </div>
          ) : null}
          {events.error === undefined ? null : (
            <Empty>
              <EmptyHeader>
                <EmptyTitle>{t("The events didn't load.")}</EmptyTitle>
              </EmptyHeader>
              <EmptyContent>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    void events.run(undefined);
                  }}
                >
                  {t("Retry")}
                </Button>
              </EmptyContent>
            </Empty>
          )}
          {rows?.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <WebhookIcon />
                </EmptyMedia>
                <EmptyTitle>{t("No webhook events yet")}</EmptyTitle>
                <EmptyDescription>
                  {t(
                    "Events appear here once a channel posts to /api/webhooks/channels.",
                  )}
                </EmptyDescription>
              </EmptyHeader>
              <EmptyContent>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    void events.run(undefined);
                  }}
                >
                  {t("Refresh")}
                </Button>
              </EmptyContent>
            </Empty>
          ) : null}
          {rows !== undefined && rows.length > 0 ? (
            <ItemGroup>
              {rows.map((row) => (
                <Item key={row.id} variant="outline" size="sm">
                  <ItemContent>
                    <ItemTitle>
                      {row.adapter}
                      <Badge variant={variantOf(row.status)}>
                        {row.status}
                      </Badge>
                    </ItemTitle>
                    <ItemDescription>
                      {format.dateTime(new Date(row.receivedAt), {
                        dateStyle: "medium",
                        timeStyle: "short",
                      })}
                      {row.attempts > 0
                        ? ` · ${t("{count, plural, one {# attempt} other {# attempts}}", { count: row.attempts })}`
                        : ""}
                      {row.error === null ? "" : ` · ${row.error}`}
                    </ItemDescription>
                  </ItemContent>
                  <ItemActions>
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={replay.pending && pendingId === row.id}
                      onClick={() => {
                        setPendingId(row.id);
                        void replay.run({ eventId: row.id });
                      }}
                    >
                      <RotateCwIcon />
                      {t("Replay")}
                    </Button>
                  </ItemActions>
                </Item>
              ))}
            </ItemGroup>
          ) : null}
        </div>
      </SheetContent>
    </Sheet>
  );
}
