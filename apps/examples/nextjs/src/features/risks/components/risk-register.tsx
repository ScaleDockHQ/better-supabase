"use client";

import { TriangleAlertIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useRouter } from "next/navigation";
import { useTransition } from "react";

import type { RecordListPage } from "@/components/record-list/record-list-types";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import { Button } from "@/components/ui/button";

import type { Loaded, RiskRow } from "../risks-queries";

import { RiskRecordList } from "./risk-record-list";

/**
 * The organization's risk register: each risk with its residual band and the
 * date of its next review, the highest residual score first.
 */
export function RiskRegister({
  state,
}: {
  state: Loaded<RecordListPage<RiskRow>>;
}) {
  const t = useExtracted("risks");
  const router = useRouter();
  const [retrying, startRetry] = useTransition();

  if (state.kind === "no-organization") {
    return null;
  }

  return (
    <Frame spacing="sm" data-recipe="risk-register">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Risk register")}</FrameTitle>
        <FrameDescription>
          {t(
            "Every identified risk with its residual rating after controls. A review moves the next review date ahead by the risk's interval.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The risk register didn't load")}</AlertTitle>
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
        ) : (
          <RiskRecordList initial={state.data} />
        )}
      </FramePanel>
    </Frame>
  );
}
