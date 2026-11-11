import { useExtracted } from "next-intl";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getProviderKeys } from "../ai-providers-queries";
import { AiProviderSettings } from "./ai-provider-settings";
import { ProviderRouting } from "./provider-routing";

const SKELETON_ROWS = ["first", "second"];

/** Render inside `<Suspense>`; the fallback is `AiProviderSettingsSkeleton`. */
export async function AiProviderSection() {
  const [read, permissions] = await Promise.all([
    getProviderKeys(),
    getPermissions(),
  ]);

  return (
    <div className="flex flex-col gap-6">
      <AiProviderSettings read={read} />
      {read.ok ? (
        <ProviderRouting
          key={read.keys
            .map((key) => `${key.id}:${key.priority}:${key.enabled}`)
            .join(",")}
          keys={read.keys}
          canManage={can(permissions, "ai_keys.manage")}
        />
      ) : null}
    </div>
  );
}

export function AiProviderSectionSkeleton() {
  const t = useExtracted("aiProviders");

  return (
    <Card aria-busy="true">
      <CardHeader>
        <CardTitle>{t("AI providers")}</CardTitle>
        <CardDescription>
          {t(
            "The organization's own provider keys, used instead of the app's key for the assistant.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-2">
        {SKELETON_ROWS.map((row) => (
          <Skeleton key={row} className="h-11 w-full" />
        ))}
      </CardContent>
    </Card>
  );
}
