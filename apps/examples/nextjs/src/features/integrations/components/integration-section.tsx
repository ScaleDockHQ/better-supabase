import { useExtracted } from "next-intl";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

import { getIntegrations } from "../integrations-queries";
import { IntegrationSettings } from "./integration-settings";

const SKELETON_ROWS = ["first", "second"];

/** Render inside `<Suspense>`; the fallback is `IntegrationSettingsSkeleton`. */
export async function IntegrationSection() {
  const read = await getIntegrations();

  return <IntegrationSettings read={read} />;
}

export function IntegrationSectionSkeleton() {
  const t = useExtracted("integrations");

  return (
    <Card aria-busy="true">
      <CardHeader>
        <CardTitle>{t("Integrations")}</CardTitle>
        <CardDescription>
          {t(
            "Your own accounts the app may use on your behalf, such as the mailbox mail sync reads.",
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
