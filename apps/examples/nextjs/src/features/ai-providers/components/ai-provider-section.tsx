import { useExtracted } from "next-intl";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

import { getProviderKeys } from "../ai-providers-queries";
import { AiProviderSettings } from "./ai-provider-settings";

const SKELETON_ROWS = ["first", "second"];

/** Render inside `<Suspense>`; the fallback is `AiProviderSettingsSkeleton`. */
export async function AiProviderSection() {
  const read = await getProviderKeys();

  return <AiProviderSettings read={read} />;
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
