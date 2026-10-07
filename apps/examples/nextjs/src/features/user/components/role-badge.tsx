"use client";

import type { Role } from "@/lib/claims";

import { Badge } from "@/components/ui/badge";
import { useRoleLabel } from "@/features/organization/use-role-label";

export function RoleBadge({ role }: { role: Role }) {
  const roleLabel = useRoleLabel();
  return (
    <Badge
      variant={role === "member" ? "secondary" : "default"}
      data-testid="role-badge"
    >
      {roleLabel(role)}
    </Badge>
  );
}
