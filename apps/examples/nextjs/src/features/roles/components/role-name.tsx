import * as v from "valibot";

import { useRoleLabel } from "@/features/organization/use-role-label";
import { Role } from "@/lib/claims";

/** A catalog role's label; a key the app doesn't know shows as itself. */
export function RoleName({ roleKey }: { roleKey: string }) {
  const roleLabel = useRoleLabel();

  return v.is(Role, roleKey) ? roleLabel(roleKey) : roleKey;
}
