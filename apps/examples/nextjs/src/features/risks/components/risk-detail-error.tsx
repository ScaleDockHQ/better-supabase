"use client";

import { TriangleAlertIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useRouter } from "next/navigation";
import { useTransition } from "react";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";

/** The inline error of a risk page, with Retry. */
export function RiskDetailError() {
  const t = useExtracted("risks");
  const router = useRouter();
  const [retrying, startRetry] = useTransition();

  return (
    <Alert variant="destructive">
      <TriangleAlertIcon />
      <AlertTitle>{t("The risk didn't load")}</AlertTitle>
      <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
      <AlertAction>
        <Button
          size="sm"
          variant="outline"
          type="button"
          disabled={retrying}
          onClick={() => {
            startRetry(() => {
              router.refresh();
            });
          }}
        >
          {t("Retry")}
        </Button>
      </AlertAction>
    </Alert>
  );
}
