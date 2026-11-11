"use client";

import { useExtracted } from "next-intl";
// oxlint-disable-next-line react-doctor/prefer-dynamic-import -- spend-chart-lazy.tsx loads this file on demand
import { Bar, BarChart, CartesianGrid, XAxis, YAxis } from "recharts";

import type { ChartConfig } from "@/components/ui/chart";

import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";

/** Cost per day. */
export function SpendChart({
  days,
}: {
  days: readonly { readonly day: string; readonly costUsd: number }[];
}) {
  const t = useExtracted("aiUsage");

  const config = {
    costUsd: { label: t("Cost (USD)"), color: "var(--chart-1)" },
  } satisfies ChartConfig;

  return (
    <ChartContainer config={config} className="h-48 w-full">
      <BarChart data={[...days]} accessibilityLayer>
        <CartesianGrid vertical={false} />
        <XAxis dataKey="day" tickLine={false} axisLine={false} />
        <YAxis tickLine={false} axisLine={false} width={48} />
        <ChartTooltip content={<ChartTooltipContent />} />
        <Bar dataKey="costUsd" fill="var(--color-costUsd)" radius={4} />
      </BarChart>
    </ChartContainer>
  );
}
