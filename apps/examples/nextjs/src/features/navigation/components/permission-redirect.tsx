"use client";

import { useEffect } from "react";

import { usePathname, useRouter } from "@/i18n/navigation";

import type { NavId } from "../nav-items";

import { activeNavId, requiredPermission } from "../nav-items";

/**
 * Sends the caller to the dashboard from a page whose menu entry needs a
 * permission they don't hold. It runs after the shell, so a full load never
 * waits on the permission read; RLS and `PermissionGate` guard the data and the
 * gated parts of the page in the meantime.
 */
export function PermissionRedirect({ allowed }: { allowed: readonly NavId[] }) {
  const pathname = usePathname();
  const { replace } = useRouter();

  useEffect(() => {
    const id = activeNavId(pathname);

    if (
      id !== undefined &&
      requiredPermission(pathname) !== undefined &&
      !allowed.includes(id)
    ) {
      replace("/");
    }
  }, [allowed, pathname, replace]);

  return null;
}
