import { useExtracted } from "next-intl";

import type { Role } from "@/lib/claims";

/** Works in Client Components and in synchronous Server Components. */
export function useRoleLabel(): (role: Role) => string {
  const t = useExtracted("organization");
  return (role) => {
    switch (role) {
      case "owner":
        return t("Owner");
      case "admin":
        return t("Admin");
      case "member":
        return t("Member");
      default: {
        const unknown: never = role;
        return unknown;
      }
    }
  };
}
