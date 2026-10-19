import { TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";

import { retryProjects } from "../project-actions";

/** The inline error of a projects region, with a Retry that reads again. */
export async function ProjectLoadError({ title }: { title: string }) {
  const t = await getExtracted("projects");

  return (
    <Alert variant="destructive">
      <TriangleAlertIcon />
      <AlertTitle>{title}</AlertTitle>
      <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
      <AlertAction>
        <form action={retryProjects}>
          <Button size="sm" variant="outline" type="submit">
            {t("Retry")}
          </Button>
        </form>
      </AlertAction>
    </Alert>
  );
}
