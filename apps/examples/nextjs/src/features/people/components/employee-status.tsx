"use client";

import type { EmployeeStatus } from "better-supabase/blocks/employees";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

export function useEmployeeStatusLabel() {
  const t = useExtracted("people");

  return (status: string): string => {
    switch (status) {
      case "active": {
        return t("Active");
      }

      case "preboarding": {
        return t("Preboarding");
      }

      case "on_leave": {
        return t("On leave");
      }

      case "offboarded": {
        return t("Offboarded");
      }

      default: {
        return status;
      }
    }
  };
}

const VARIANTS = {
  active: "success-light",
  preboarding: "info-light",
  on_leave: "warning-light",
  offboarded: "secondary",
} as const satisfies Record<EmployeeStatus, string>;

export function EmployeeStatusBadge({ status }: { status: EmployeeStatus }) {
  const label = useEmployeeStatusLabel();

  return <Badge variant={VARIANTS[status]}>{label(status)}</Badge>;
}
