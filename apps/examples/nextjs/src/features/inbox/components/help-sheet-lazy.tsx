"use client";

import { LifeBuoyIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { lazy } from "react";

import { LazyOnIntent } from "@/components/lazy-on-intent";
import { Button } from "@/components/ui/button";

const HelpSheet = lazy(() =>
  import("./help-sheet").then((mod) => ({ default: mod.HelpSheet })),
);

/**
 * The Help button. The sheet, the inbox widget hook and the composer load on
 * the first hover, focus or click.
 */
export function HelpSheetLazy() {
  const t = useExtracted("inbox");

  return (
    <LazyOnIntent
      renderTrigger={(handlers) => (
        <Button
          variant="ghost"
          size="sm"
          aria-label={t("Help")}
          aria-haspopup="dialog"
          {...handlers}
        >
          <LifeBuoyIcon />
          <span className="hidden sm:inline">{t("Help")}</span>
        </Button>
      )}
    >
      <HelpSheet />
    </LazyOnIntent>
  );
}
