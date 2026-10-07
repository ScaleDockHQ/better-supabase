import { LifeBuoyIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";

import { getSession } from "../user-queries";

/**
 * Shown during a support session (`bs.startSupport`): staff see the app as
 * the user, and the audit log records who acted. Render inside `<Suspense>`.
 */
export async function ImpersonationBanner() {
  const session = await getSession();
  if (session.kind !== "user" || !session.impersonator) return null;
  const t = await getExtracted("user");
  const { id, reason } = session.impersonator;
  return (
    <Alert variant="destructive" data-testid="impersonation">
      <LifeBuoyIcon />
      <AlertTitle>{t("Support session")}</AlertTitle>
      <AlertDescription>
        {reason
          ? t("Signed in by support ({id}): {reason}", { id, reason })
          : t("Signed in by support ({id}).", { id })}
      </AlertDescription>
    </Alert>
  );
}
