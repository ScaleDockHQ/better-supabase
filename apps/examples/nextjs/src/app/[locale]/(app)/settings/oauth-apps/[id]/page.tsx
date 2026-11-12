import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { AdminBackLink } from "@/features/admin-lists/admin-detail-page";
import {
  OAuthAppDetail,
  OAuthAppDetailSkeleton,
} from "@/features/oauth-apps/components/oauth-app-detail";

// A navigation here shows the back link at once; the app streams in.
export const instant = true;

export default function OAuthAppDetailPage({
  params,
}: PageProps<"/[locale]/settings/oauth-apps/[id]">) {
  const t = useExtracted("oauthApps");

  return (
    <>
      <AdminBackLink href="/settings/oauth-apps">{t("All apps")}</AdminBackLink>
      <Suspense fallback={<OAuthAppDetailSkeleton />}>
        {params.then(({ id }) => (
          <OAuthAppDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
