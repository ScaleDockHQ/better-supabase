import { TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";

import { retryIslands } from "../islands-actions";

/** The inline error of one island, with a Retry that reads it again. */
export async function IslandError({ title }: { title: string }) {
  const t = await getExtracted("islands");

  return (
    <Alert variant="destructive" data-testid="island-error">
      <TriangleAlertIcon />
      <AlertTitle>{title}</AlertTitle>
      <AlertDescription>{t("This island could not load.")}</AlertDescription>
      <AlertAction>
        <form action={retryIslands}>
          <Button size="sm" variant="outline" type="submit">
            {t("Retry")}
          </Button>
        </form>
      </AlertAction>
    </Alert>
  );
}
