import { TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";
import { unstable_rethrow } from "next/navigation";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

import type { CurrentSession, OtherSession } from "../sessions-queries";

import { getCurrentSession, getOtherSessions } from "../sessions-queries";
import { SessionsList } from "./sessions-list";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

async function loadSession(): Promise<
  | {
      kind: "ok";
      session: CurrentSession | null;
      others: readonly OtherSession[];
    }
  | { kind: "error" }
> {
  try {
    const [session, others] = await Promise.all([
      getCurrentSession(),
      getOtherSessions(),
    ]);

    return { kind: "ok", session, others };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

export async function SessionsCard() {
  const [t, result] = await Promise.all([
    getExtracted("sessions"),
    loadSession(),
  ]);

  if (result.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("Your sessions could not be loaded")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
        <AlertAction>
          <form action={retry}>
            <Button size="sm" variant="outline" type="submit">
              {t("Retry")}
            </Button>
          </form>
        </AlertAction>
      </Alert>
    );
  }

  return result.session ? (
    <SessionsList session={result.session} others={result.others} />
  ) : null;
}

export function SessionsCardSkeleton() {
  return <Skeleton className="h-48 rounded-xl" aria-busy="true" />;
}
