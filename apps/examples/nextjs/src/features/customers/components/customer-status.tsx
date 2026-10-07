"use client";

import { Badge } from "@/components/ui/badge";

import { useStatusLabel } from "../use-status-label";

export function CustomerStatus({ status }: { status: string }) {
  const statusLabel = useStatusLabel();
  return (
    <Badge
      variant={status === "active" ? "default" : "secondary"}
      className="ml-auto"
    >
      {statusLabel(status)}
    </Badge>
  );
}
