import { getExtracted } from "next-intl/server";

import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { activeOrganizationId, can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { getApiKeys } from "../api-key-queries";
import { ApiKeyTable } from "./api-key-table";
import { CreateApiKeyDialog } from "./create-api-key-dialog";

/** Render inside `<Suspense>`; the fallback is `ApiKeysSectionSkeleton`. */
export async function ApiKeysSection() {
  const session = await getSession();
  const organizationId = activeOrganizationId(session);
  if (!organizationId) return null;
  const [keys, t] = await Promise.all([
    getApiKeys(organizationId),
    getExtracted("apiKeys"),
  ]);
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
        <CardAction>
          <CreateApiKeyDialog />
        </CardAction>
      </CardHeader>
      <CardContent>
        <ApiKeyTable keys={keys} />
      </CardContent>
    </Card>
  );
}

export function ApiKeysSectionSkeleton() {
  return <Skeleton className="h-72 rounded-xl" aria-busy="true" />;
}
