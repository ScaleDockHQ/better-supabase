import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { AdminBackLink } from "@/features/admin-lists/admin-detail-page";
import {
  ConnectorDetail,
  ConnectorDetailSkeleton,
} from "@/features/integrations/components/connector-detail";

// A navigation here shows the back link at once; the connector streams in.
export const instant = true;

export default function ConnectorPage({
  params,
}: PageProps<"/[locale]/settings/integrations/[id]">) {
  const t = useExtracted("integrations");

  return (
    <>
      <AdminBackLink href="/settings/integrations">
        {t("All integrations")}
      </AdminBackLink>
      <Suspense fallback={<ConnectorDetailSkeleton />}>
        {params.then(({ id }) => (
          <ConnectorDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
