import { tenantOf } from "better-supabase/next";
import { getExtracted } from "next-intl/server";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { ApiKeyTable } from "./api-key-table";

/** Render inside `<Suspense>`; the fallback is `ApiKeysSectionSkeleton`. */
export async function ApiKeysSection() {
  const [session, t] = await Promise.all([
    getSession(),
    getExtracted("apiKeys"),
  ]);
  const organizationId = tenantOf(session);
  if (!organizationId) {
    return null;
  }
  const manage = can(session, "api_keys.manage");
  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("API keys")}</CardTitle>
        <CardDescription>
          {manage
            ? t(
                "Organization keys act for the organization. Verified by the api-keys module.",
              )
            : t("Personal keys act as you, with your role.")}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ApiKeyTable organizationId={organizationId} personal={!manage} />
      </CardContent>
    </Card>
  );
}

export function ApiKeysSectionSkeleton() {
  return <Skeleton className="h-72 rounded-xl" aria-busy="true" />;
}
