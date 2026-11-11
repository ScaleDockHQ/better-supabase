"use client";

import { TriangleAlertIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";

/**
 * The inline error of a section, with Retry. `retryAction` is a Server Action
 * that refreshes the record's cache tag.
 */
export function RecordSectionError({
  title,
  retryAction,
}: {
  title: string;
  retryAction: () => Promise<void>;
}) {
  const t = useExtracted("recordDetail");

  return (
    <Alert variant="destructive">
      <TriangleAlertIcon />
      <AlertTitle>{title}</AlertTitle>
      <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
      <AlertAction>
        <form action={retryAction}>
          <Button size="sm" variant="outline" type="submit">
            {t("Retry")}
          </Button>
        </form>
      </AlertAction>
    </Alert>
  );
}
