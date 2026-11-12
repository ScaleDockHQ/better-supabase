import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  SessionDetail,
  SessionDetailSkeleton,
} from "@/features/checkout-sessions/components/session-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

// A navigation shows the back link at once; the session streams in.
export const instant = true;

export default function CheckoutSessionPage({
  params,
}: PageProps<"/[locale]/shop/checkout-sessions/[id]">) {
  const t = useExtracted("checkoutSessions");

  return (
    <>
      <Link
        href="/shop/checkout-sessions"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All sessions")}
      </Link>
      <Suspense fallback={<SessionDetailSkeleton />}>
        <PermissionGate permission="agent_checkout.read">
          {params.then(({ id }) => (
            <SessionDetail id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
