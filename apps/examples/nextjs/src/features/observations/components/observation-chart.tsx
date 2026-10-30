import type { ObservationFlag } from "better-supabase/blocks/observations";

import { HeartPulseIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

import { getVitals } from "../observations-queries";

// #region recipe:observation-chart
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

const FLAG_VARIANT = {
  normal: "success-light",
  low: "warning-light",
  high: "warning-light",
  critical_low: "destructive",
  critical_high: "destructive",
} as const satisfies Record<ObservationFlag, string>;

const WIDTH = 120;
const HEIGHT = 32;

/** The values as an SVG polyline, scaled to the box. */
function Sparkline({
  values,
  label,
}: {
  readonly values: readonly number[];
  readonly label: string;
}) {
  if (values.length < 2) {
    return null;
  }

  const low = Math.min(...values);
  const span = Math.max(...values) - low || 1;
  const step = WIDTH / (values.length - 1);

  const points = values
    .map(
      (value, index) =>
        `${(index * step).toFixed(1)},${(HEIGHT - 2 - ((value - low) / span) * (HEIGHT - 4)).toFixed(1)}`,
    )
    .join(" ");

  return (
    <>
      <span className="sr-only">{label}</span>
      <svg
        aria-hidden="true"
        viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
        className="h-8 w-30 text-primary"
      >
        <polyline
          points={points}
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
          strokeLinejoin="round"
          strokeLinecap="round"
        />
      </svg>
    </>
  );
}

/**
 * Render inside `<Suspense>`: a record's latest vital signs, each with its flag
 * against the reference range and a sparkline of its recent values.
 */
export async function ObservationChart() {
  const [state, t, format] = await Promise.all([
    getVitals(),
    getExtracted("observations"),
    getFormatter(),
  ]);

  if (state.kind === "no-organization") {
    return null;
  }

  if (state.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="observation-chart">
        <TriangleAlertIcon />
        <AlertTitle>{t("The vital signs didn't load")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
        <AlertAction>
          <form action={retry}>
            <Button size="sm" variant="outline" type="submit">
              {t("Retry")}
            </Button>
          </form>
        </AlertAction>
      </Alert>
    );
  }

  const { customer, rows } = state.data;

  const flagLabel = (flag: ObservationFlag): string => {
    switch (flag) {
      case "normal": {
        return t("Normal");
      }

      case "low": {
        return t("Low");
      }

      case "high": {
        return t("High");
      }

      case "critical_low": {
        return t("Critically low");
      }

      case "critical_high": {
        return t("Critically high");
      }

      default: {
        const unknown: never = flag;

        return unknown;
      }
    }
  };

  return (
    <Frame spacing="sm" data-recipe="observation-chart">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Vital signs")}</FrameTitle>
        <FrameDescription>
          {customer === null
            ? t("The latest readings of a customer, against their ranges.")
            : t("The latest readings for {name}, against their ranges.", {
                name: customer.name,
              })}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {rows.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <HeartPulseIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No readings yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Recorded vital signs appear here with their flag and recent trend.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/observations#record"
              >
                {t("Read how to record an observation")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <Table aria-label={t("Latest vital signs")}>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Measurement")}</TableHead>
                <TableHead>{t("Latest")}</TableHead>
                <TableHead>{t("Flag")}</TableHead>
                <TableHead>{t("Trend")}</TableHead>
                <TableHead>{t("Observed")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((row) => (
                <TableRow key={row.key}>
                  <TableCell className="font-medium">{row.title}</TableCell>
                  <TableCell className="tabular-nums">
                    {row.unit === null ? row.value : `${row.value} ${row.unit}`}
                  </TableCell>
                  <TableCell>
                    {row.flag === null ? null : (
                      <Badge variant={FLAG_VARIANT[row.flag]}>
                        {flagLabel(row.flag)}
                      </Badge>
                    )}
                  </TableCell>
                  <TableCell>
                    <Sparkline
                      values={row.series}
                      label={t("{title}: the last {count, number} readings", {
                        title: row.title,
                        count: row.series.length,
                      })}
                    />
                  </TableCell>
                  <TableCell className="text-muted-foreground">
                    {format.dateTime(new Date(row.observedAt), {
                      dateStyle: "medium",
                      timeStyle: "short",
                    })}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </FramePanel>
    </Frame>
  );
}
// #endregion recipe:observation-chart

export function ObservationChartSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-24" />
        <Skeleton className="h-4 w-64" />
      </FrameHeader>
      <FramePanel>
        <Skeleton className="h-64" />
      </FramePanel>
    </Frame>
  );
}
