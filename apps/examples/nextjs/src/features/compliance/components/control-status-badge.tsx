import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

import type { ControlRow } from "../compliance-queries";

const STATUS_VARIANT: Record<
  ControlRow["status"],
  "destructive-light" | "secondary" | "success-light"
> = {
  passing: "success-light",
  failing: "destructive-light",
  not_started: "secondary",
  not_applicable: "secondary",
};

export function ControlStatusBadge({
  status,
}: {
  status: ControlRow["status"];
}) {
  const t = useExtracted("compliance");

  const labels: Record<ControlRow["status"], string> = {
    passing: t("Passing"),
    failing: t("Failing"),
    not_started: t("Not started"),
    not_applicable: t("Not applicable"),
  };

  return <Badge variant={STATUS_VARIANT[status]}>{labels[status]}</Badge>;
}
