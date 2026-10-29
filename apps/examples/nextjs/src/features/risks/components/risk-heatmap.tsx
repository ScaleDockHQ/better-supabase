import { GridIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
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

import { getRiskHeatmap } from "../risks-queries";

// #region recipe:risk-heatmap
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

const TONE_VARIANT = {
  low: "success-light",
  medium: "warning-light",
  high: "destructive-light",
  critical: "destructive",
} as const;

/**
 * Render inside `<Suspense>`: the open risks on the default matrix, one cell
 * per likelihood and impact, colored by the cell's band. The highest likelihood
 * is the top row.
 */
export async function RiskHeatmap() {
  const [state, t] = await Promise.all([
    getRiskHeatmap(),
    getExtracted("risks"),
  ]);

  if (state.kind === "no-organization") {
    return null;
  }

  if (state.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="risk-heatmap">
        <TriangleAlertIcon />
        <AlertTitle>{t("The heatmap didn't load")}</AlertTitle>
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

  const { matrixName, likelihoods, impacts, cells, total } = state.data;

  const cellAt = new Map(
    cells.map((cell) => [`${cell.likelihood}:${cell.impact}`, cell]),
  );

  return (
    <Frame spacing="sm" data-recipe="risk-heatmap">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Heatmap")}</FrameTitle>
        <FrameDescription>
          {t(
            "{total, plural, =0 {No open risks} one {# open risk} other {# open risks}} on the {matrix} matrix, by residual rating.",
            { total, matrix: matrixName },
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {total === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <GridIcon />
              </EmptyMedia>
              <EmptyTitle>{t("Nothing assessed yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Assessed risks appear here in the cell of their residual likelihood and impact.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/risks#assess"
              >
                {t("Read how assessment works")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <Table aria-label={t("Risks by likelihood and impact")}>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Likelihood / impact")}</TableHead>
                {impacts.map((impact) => (
                  <TableHead key={impact.level} className="text-center">
                    {impact.label}
                  </TableHead>
                ))}
              </TableRow>
            </TableHeader>
            <TableBody>
              {likelihoods.toReversed().map((likelihood) => (
                <TableRow key={likelihood.level}>
                  <TableHead scope="row">{likelihood.label}</TableHead>
                  {impacts.map((impact) => {
                    const cell = cellAt.get(
                      `${likelihood.level}:${impact.level}`,
                    );

                    return (
                      <TableCell key={impact.level} className="text-center">
                        {cell ? (
                          <Badge
                            variant={TONE_VARIANT[cell.tone]}
                            aria-label={t(
                              "{band}: {count, plural, one {# risk} other {# risks}}",
                              { band: cell.band, count: cell.count },
                            )}
                          >
                            {cell.count}
                          </Badge>
                        ) : null}
                      </TableCell>
                    );
                  })}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </FramePanel>
    </Frame>
  );
}
// #endregion recipe:risk-heatmap

export function RiskHeatmapSkeleton() {
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
