"use client";

import { useExtracted } from "next-intl";
// oxlint-disable-next-line react-doctor/prefer-dynamic-import -- pass-rate-chart-lazy.tsx loads this file on demand
import { Bar, BarChart, CartesianGrid, XAxis, YAxis } from "recharts";

import type { ChartConfig } from "@/components/ui/chart";

import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";

/** The pass rate of each run, oldest first. */
export function PassRateChart({
  points,
}: {
  points: readonly { readonly label: string; readonly passRate: number }[];
}) {
  const t = useExtracted("evals");

  const config = {
    passRate: { label: t("Pass rate"), color: "var(--chart-1)" },
  } satisfies ChartConfig;

  return (
    <ChartContainer config={config} className="h-48 w-full">
      <BarChart data={[...points]} accessibilityLayer>
        <CartesianGrid vertical={false} />
        <XAxis dataKey="label" tickLine={false} axisLine={false} />
        <YAxis
          domain={[0, 100]}
          tickLine={false}
          axisLine={false}
          width={32}
          unit="%"
        />
        <ChartTooltip content={<ChartTooltipContent />} />
        <Bar dataKey="passRate" fill="var(--color-passRate)" radius={4} />
      </BarChart>
    </ChartContainer>
  );
}
