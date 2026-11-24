"use client";

import { XIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";

/**
 * The bar above a list while rows are ticked: the count, a clear button and the
 * bulk actions the feature passes in (each one a Server Action button). It
 * renders nothing without a selection, so the list keeps its height.
 */
export function RecordBulkBar({
  count,
  onClear,
  children,
}: {
  count: number;
  onClear: () => void;
  children?: React.ReactNode;
}) {
  const t = useExtracted("recordList");

  if (count === 0) {
    return null;
  }

  return (
    <section
      aria-label={t("Bulk actions")}
      className="flex flex-wrap items-center gap-2 rounded-xl bg-muted px-3 py-2 text-sm"
      data-testid="bulk-bar"
    >
      <span className="font-medium tabular-nums">
        {t("{count} selected", { count: String(count) })}
      </span>
      <Button size="sm" variant="ghost" onClick={onClear}>
        <XIcon />
        {t("Clear")}
      </Button>
      <div className="ml-auto flex items-center gap-2">{children}</div>
    </section>
  );
}
