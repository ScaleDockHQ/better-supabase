"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { TimerIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { Loaded } from "@/features/records/records-queries";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import {
  RecordCardSkeleton,
  RecordLoadError,
} from "@/features/records/components/record-card-states";
import { toast } from "@/lib/toast";

import type { SlaClockRow } from "../customers-queries";

import { startCustomerSla } from "../customers-actions";

// #region recipe:sla-badges

const VARIANT = {
  running: "info-light",
  paused: "secondary",
  met: "success-light",
  breached: "destructive-light",
} as const satisfies Record<SlaClockRow["state"], string>;

/**
 * The customer's SLA clocks as badges. Without clocks, the empty state starts
 * them; with no policy for customers, a caller who manages SLAs gets a default
 * policy first.
 */
export function SlaBadges({
  customerId,
  clocks,
  canCreatePolicy,
}: {
  customerId: string;
  clocks: Loaded<readonly SlaClockRow[]>;
  canCreatePolicy: boolean;
}) {
  const t = useExtracted("customers");
  const format = useFormatter();
  const errorMessage = useErrorMessage();

  const start = useAction(startCustomerSla, {
    onSuccess: (count) => {
      if (count === 0) {
        toast.error(t("No SLA policy covers customers yet."));
      } else {
        toast.success(t("SLA clocks started"));
      }
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const metric = {
    first_response: t("First response"),
    next_response: t("Next response"),
    resolution: t("Resolution"),
  } as const satisfies Record<SlaClockRow["metric"], string>;

  const state = {
    running: t("On track"),
    paused: t("Paused"),
    met: t("Met"),
    breached: t("Breached"),
  } as const satisfies Record<SlaClockRow["state"], string>;

  const timing = (clock: SlaClockRow): string => {
    if (clock.state === "met") {
      return t("Done");
    }

    if (clock.secondsLeft === null || clock.state === "paused") {
      return t("Due {date}", {
        date: format.dateTime(clock.dueAt, {
          dateStyle: "medium",
          timeStyle: "short",
        }),
      });
    }

    const minutes = Math.round(Math.abs(clock.secondsLeft) / 60);

    const span =
      minutes >= 1440
        ? format.number(Math.round(minutes / 1440), {
            style: "unit",
            unit: "day",
            unitDisplay: "long",
          })
        : minutes >= 60
          ? format.number(Math.round(minutes / 60), {
              style: "unit",
              unit: "hour",
              unitDisplay: "long",
            })
          : format.number(minutes, {
              style: "unit",
              unit: "minute",
              unitDisplay: "long",
            });

    return clock.secondsLeft < 0
      ? t("{span} overdue", { span })
      : t("{span} left", { span });
  };

  return (
    <Card size="sm" data-recipe="sla-badges">
      <CardHeader>
        <CardTitle>{t("SLA")}</CardTitle>
      </CardHeader>
      <CardContent>
        {clocks.kind === "error" ? (
          <RecordLoadError title={t("The SLA clocks didn't load")} />
        ) : clocks.data.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <TimerIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No SLA clocks")}</EmptyTitle>
              <EmptyDescription>
                {canCreatePolicy
                  ? t(
                      "Start the clocks. Without a policy for customers, a default one is created: first response in 4 hours, resolution in 3 days.",
                    )
                  : t("Start the clocks of the policy that covers customers.")}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Button
                size="sm"
                disabled={start.pending}
                onClick={() => {
                  void start.run({ customerId });
                }}
              >
                <TimerIcon />
                {t("Start SLA clocks")}
              </Button>
            </EmptyContent>
          </Empty>
        ) : (
          <ul className="flex flex-col gap-2" data-testid="sla-clocks">
            {clocks.data.map((clock) => (
              <li
                key={clock.id}
                className="flex items-center justify-between gap-2"
              >
                <div className="flex min-w-0 flex-col gap-1">
                  <span className="text-sm font-medium">
                    {metric[clock.metric]}
                  </span>
                  <span className="text-xs text-muted-foreground">
                    {timing(clock)}
                  </span>
                </div>
                <Badge variant={VARIANT[clock.state]}>
                  {state[clock.state]}
                </Badge>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}

/** The SLA card while its clocks load. */
export function SlaBadgesSkeleton() {
  return <RecordCardSkeleton rows={2} />;
}

// #endregion recipe:sla-badges
