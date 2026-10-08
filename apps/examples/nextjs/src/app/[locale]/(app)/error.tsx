"use client";

import { TriangleAlertIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";

/**
 * A thrown error below the app layout: the sidebar stays, `retry()`
 * re-fetches the segment. Expected failures are `ActionResult` errors and
 * never reach this boundary.
 */
export default function AppError({
  error,
  retry,
}: {
  error: Error & { digest?: string };
  retry: () => void;
}) {
  const t = useExtracted("app");
  return (
    <Empty role="alert" className="m-6 border">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <TriangleAlertIcon />
        </EmptyMedia>
        <EmptyTitle>{t("Something went wrong")}</EmptyTitle>
        <EmptyDescription>
          {error.digest === undefined
            ? t("Try again in a moment.")
            : t("Try again in a moment. Reference: {digest}", {
                digest: error.digest,
              })}
        </EmptyDescription>
      </EmptyHeader>
      <EmptyContent>
        <Button onClick={retry}>{t("Try again")}</Button>
      </EmptyContent>
    </Empty>
  );
}
