"use client";

import type { DbError } from "better-supabase";
import type { PreparationState } from "better-supabase/blocks/orders";

import { useAction } from "better-supabase/react";
import { useExtracted, useFormatter } from "next-intl";
import { toast } from "sonner";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { useErrorMessage } from "@/lib/use-error-message";

import type { TicketView } from "../kitchen-queries";

import { bumpTicket, setLineState } from "../kitchen-actions";
import {
  nextPreparationState,
  preparationBadgeVariant,
  usePreparationLabel,
} from "./kitchen-labels";

const RANK: Record<PreparationState, number> = {
  queued: 0,
  preparing: 1,
  ready: 2,
  served: 3,
};

/** One order's lines at a station, with a button for the ticket's next step. */
export function KitchenTicket({
  ticket,
  stationId,
  canPrepare,
}: {
  ticket: TicketView;
  stationId: string | null;
  canPrepare: boolean;
}) {
  const t = useExtracted("shop");
  const format = useFormatter();
  const label = usePreparationLabel();
  const errorMessage = useErrorMessage();

  const onError = (error: DbError) => {
    toast.error(errorMessage(error));
  };

  const bump = useAction(bumpTicket, { onError });
  const line = useAction(setLineState, { onError });
  const pending = bump.pending || line.pending;

  const least = ticket.lines.reduce<PreparationState>(
    (state, each) => (RANK[each.state] < RANK[state] ? each.state : state),
    "served",
  );

  const next = nextPreparationState(least);

  const action =
    next === "preparing"
      ? t("Start")
      : next === "ready"
        ? t("Mark ready")
        : t("Serve");

  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle className="tabular-nums">
          {t("Order {number}", { number: ticket.number })}
        </CardTitle>
        <CardDescription className="tabular-nums">
          {t("Sent at {time}", {
            time: format.dateTime(new Date(ticket.sentAt), {
              timeStyle: "short",
            }),
          })}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ul className="flex flex-col gap-2">
          {ticket.lines.map((each) => {
            const after = nextPreparationState(each.state);

            return (
              <li
                key={each.lineId}
                className="flex items-start justify-between gap-2"
              >
                <div className="flex min-w-0 flex-col gap-0.5">
                  <span className="text-sm font-medium">
                    <span className="tabular-nums">{each.quantity}</span>
                    {" × "}
                    {each.title}
                  </span>
                  {each.note === null ? null : (
                    <span className="text-xs text-muted-foreground">
                      {each.note}
                    </span>
                  )}
                </div>
                {canPrepare && after !== null ? (
                  <button
                    type="button"
                    disabled={pending}
                    aria-label={t("Move {title} to {state}", {
                      title: each.title,
                      state: label(after),
                    })}
                    onClick={() => {
                      void line.run({ lineId: each.lineId, state: after });
                    }}
                  >
                    <Badge variant={preparationBadgeVariant(each.state)}>
                      {label(each.state)}
                    </Badge>
                  </button>
                ) : (
                  <Badge variant={preparationBadgeVariant(each.state)}>
                    {label(each.state)}
                  </Badge>
                )}
              </li>
            );
          })}
        </ul>
      </CardContent>
      {canPrepare && next !== null ? (
        <CardFooter>
          <Button
            size="sm"
            className="w-full"
            disabled={pending}
            onClick={() => {
              void bump.run({
                orderId: ticket.orderId,
                state: next,
                stationId,
              });
            }}
          >
            {action}
          </Button>
        </CardFooter>
      ) : null}
    </Card>
  );
}
