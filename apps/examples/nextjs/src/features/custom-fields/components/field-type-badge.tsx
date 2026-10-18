"use client";

import { Badge } from "@/components/reui/badge";

import { useTypeLabel } from "./custom-field-controls";

export function FieldTypeBadge({ type }: { type: string }) {
  const typeLabel = useTypeLabel();

  return <Badge variant="outline">{typeLabel(type)}</Badge>;
}
