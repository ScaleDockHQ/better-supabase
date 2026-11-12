import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

import type { BandTone } from "../risk-rows";

const TONE_VARIANT = {
  low: "success-light",
  medium: "warning-light",
  high: "destructive-light",
  critical: "destructive",
} as const satisfies Record<BandTone, string>;

/** A residual band as a Badge, or "Not assessed" before the first assessment. */
export function RiskBandBadge({
  band,
  tone,
  score,
}: {
  band: string | null;
  tone: BandTone | null;
  score: number | null;
}) {
  const t = useExtracted("risks");

  return band === null || tone === null ? (
    <span className="text-muted-foreground">{t("Not assessed")}</span>
  ) : (
    <Badge variant={TONE_VARIANT[tone]}>
      {t("{band} · {score, number}", { band, score: score ?? 0 })}
    </Badge>
  );
}
