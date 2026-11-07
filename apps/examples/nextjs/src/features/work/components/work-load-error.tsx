import { TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";

import { retryWork } from "../work-actions";

// skeleton: renders from props and translations, so nothing of its own suspends
/** The inline error of a work region, with a Retry that reads again. */
export async function WorkLoadError({ title }: { title: string }) {
  const t = await getExtracted("work");

  return (
    <Alert variant="destructive">
      <TriangleAlertIcon />
      <AlertTitle>{title}</AlertTitle>
      <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
      <AlertAction>
        <form action={retryWork}>
          <Button size="sm" variant="outline" type="submit">
            {t("Retry")}
          </Button>
        </form>
      </AlertAction>
    </Alert>
  );
}
