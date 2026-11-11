"use client";

import type { CellContext } from "@tanstack/react-table";
import type { EvalComparison } from "better-supabase/blocks/ai-evals";

import { ClipboardCheckIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useQueryStates } from "nuqs";
import { useTransition } from "react";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListGrid } from "@/components/record-list/record-list-grid";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

import type { EvalResultRow } from "../evals-queries";

import { evalSearchParams } from "../evals-search-params";

type Row = EvalResultRow & { readonly id: string };

type ResultCell = CellContext<ReadOnlyGridFeatures, Row>;

function InputCell({ row }: ResultCell) {
  return <span className="line-clamp-2">{row.original.input}</span>;
}

function ExpectedCell({ row }: ResultCell) {
  return (
    <span className="line-clamp-2 text-muted-foreground">
      {row.original.expected}
    </span>
  );
}

function OutputCell({ row }: ResultCell) {
  const { output, error } = row.original;

  return (
    <span className="line-clamp-2 text-muted-foreground">
      {error ?? output}
    </span>
  );
}

function VerdictCell({ row }: ResultCell) {
  const t = useExtracted("evals");

  return row.original.passed ? (
    <Badge variant="success-light">{t("Passed")}</Badge>
  ) : (
    <Badge variant="destructive-light">{t("Failed")}</Badge>
  );
}

function LatencyCell({ row }: ResultCell) {
  const { latencyMs } = row.original;

  return (
    <span className="text-muted-foreground tabular-nums">
      {latencyMs === undefined ? "–" : `${latencyMs} ms`}
    </span>
  );
}

/** The results of the selected run, and how it compares with the run before it. */
export function EvalResults({
  results,
  comparison,
  failedOnly,
}: {
  results: readonly EvalResultRow[];
  comparison: EvalComparison | undefined;
  failedOnly: boolean;
}) {
  const t = useExtracted("evals");
  const format = useFormatter();
  const [pending, startTransition] = useTransition();

  const [, setState] = useQueryStates(evalSearchParams, {
    shallow: false,
    startTransition,
  });

  const columns: RecordListColumns<Row> = [
    { accessorKey: "input", header: t("Input"), size: 260, cell: InputCell },
    {
      accessorKey: "expected",
      header: t("Expected"),
      size: 200,
      cell: ExpectedCell,
    },
    { accessorKey: "output", header: t("Output"), size: 240, cell: OutputCell },
    {
      accessorKey: "passed",
      header: t("Result"),
      size: 100,
      cell: VerdictCell,
    },
    {
      accessorKey: "latencyMs",
      header: t("Latency"),
      size: 100,
      cell: LatencyCell,
    },
  ];

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Results")}</CardTitle>
        <CardDescription>
          {comparison === undefined
            ? t("The first run has nothing to compare with.")
            : t(
                "{delta} against the run before, with {regressions, number} regressions and {improvements, number} improvements.",
                {
                  delta: format.number(comparison.passRateDelta, {
                    style: "percent",
                    signDisplay: "exceptZero",
                  }),
                  regressions: comparison.regressions.length,
                  improvements: comparison.improvements.length,
                },
              )}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <div className="flex justify-end">
          <Button
            size="sm"
            variant={failedOnly ? "secondary" : "outline"}
            aria-pressed={failedOnly}
            onClick={() => {
              void setState({ failed: !failedOnly });
            }}
          >
            {t("Only failures")}
          </Button>
        </div>
        <RecordListGrid
          rows={results.map((result) => ({ ...result, id: result.itemId }))}
          columns={columns}
          failed={false}
          pending={pending}
          emptyIcon={<ClipboardCheckIcon />}
          emptyTitle={failedOnly ? t("No failures") : t("No results yet")}
          emptyDescription={
            failedOnly
              ? t("Every item of this run passed.")
              : t("Results appear as the run answers each item.")
          }
          emptyAction={null}
          onRetry={() => undefined}
        />
      </CardContent>
    </Card>
  );
}
