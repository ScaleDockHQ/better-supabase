"use client";

import { Badge } from "@/components/reui/badge";

import type { TaskStatus } from "../project-types";

import { statusBadgeVariant, useStatusLabel } from "../use-task-labels";

export function TaskStatusBadge({ status }: { status: TaskStatus }) {
  const statusLabel = useStatusLabel();

  return (
    <Badge variant={statusBadgeVariant(status)}>{statusLabel(status)}</Badge>
  );
}
