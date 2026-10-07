import { FlaskConicalIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

import { getEnabledFlags } from "../flag-queries";

/**
 * Render inside `<Suspense>`. The sidebar hides the link while the flag is
 * off; this answers 404 for a direct visit too.
 */
export async function BetaContent() {
  const flags = await getEnabledFlags();
  if (!flags.includes("beta-page")) notFound();
  const t = await getExtracted("beta");
  return (
    <Card data-testid="beta">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <FlaskConicalIcon className="size-4" />
          {t("You're in the beta")}
        </CardTitle>
        <CardDescription>
          {t(
            "The beta-page flag is on for your organization, through an override in the flags module.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent className="text-muted-foreground text-sm">
        {t(
          "Turn it off with better_supabase.set_flag_override, and this page and its menu entry disappear on the next session refresh.",
        )}
      </CardContent>
    </Card>
  );
}

export function BetaContentSkeleton() {
  return <Skeleton className="h-40 rounded-xl" aria-busy="true" />;
}
