import type { ReactNode } from "react";

import { TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";

import type { FinanceEntityKey } from "@/lib/finance-list";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";

import { getFinanceFirstPage } from "../finance-records-queries";
import { FinanceRecordList } from "./finance-record-list";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/**
 * The overview of one finance entity on the list kit, for the page's
 * `<Suspense>`; the fallback is `FinanceListSkeleton`. `create` is the entity's
 * create action, shown in the empty state.
 */
export async function FinanceList({
  entity,
  create,
}: {
  entity: FinanceEntityKey;
  create?: ReactNode;
}) {
  const [page, t] = await Promise.all([
    getFinanceFirstPage(entity),
    getExtracted("finance"),
  ]);

  if (page.kind === "no-organization") {
    return null;
  }

  if (page.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The list did not load")}</AlertTitle>
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

  return (
    <FinanceRecordList
      entity={entity}
      initial={page.data}
      emptyAction={create}
    />
  );
}

export function FinanceListSkeleton() {
  return <RecordListSkeleton rows={5} />;
}
