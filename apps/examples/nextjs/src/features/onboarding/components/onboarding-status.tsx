"use client";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

import type { OnboardingRow } from "../onboarding-list";

export function useOnboardingStatusLabel() {
  const t = useExtracted("people");

  return (status: string): string => {
    switch (status) {
      case "active": {
        return t("In progress");
      }

      case "completed": {
        return t("Completed");
      }

      case "cancelled": {
        return t("Cancelled");
      }

      default: {
        return status;
      }
    }
  };
}

const VARIANTS = {
  active: "info-light",
  completed: "success-light",
  cancelled: "secondary",
} as const satisfies Record<OnboardingRow["status"], string>;

export function OnboardingStatusBadge({
  status,
}: {
  status: OnboardingRow["status"];
}) {
  const label = useOnboardingStatusLabel();

  return <Badge variant={VARIANTS[status]}>{label(status)}</Badge>;
}
