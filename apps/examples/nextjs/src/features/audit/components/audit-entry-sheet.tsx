"use client";

import type { ReactNode } from "react";

import { useExtracted } from "next-intl";
import { useQueryState } from "nuqs";
import { startTransition } from "react";

import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";

import { auditSearchParams } from "../audit-search-params";

/**
 * The details of one entry, open while `?entry=` names it. The server renders
 * the children (`AuditEntryDetails`) only for that entry.
 */
export function AuditEntrySheet({ children }: { children?: ReactNode }) {
  const t = useExtracted("audit");

  const [entry, setEntry] = useQueryState("entry", {
    ...auditSearchParams.entry,
    shallow: false,
    startTransition,
  });

  return (
    <Sheet
      open={entry !== null}
      onOpenChange={(open) => {
        if (!open) {
          void setEntry(null);
        }
      }}
    >
      <SheetContent className="overflow-y-auto">
        <SheetHeader>
          <SheetTitle>{t("Entry")}</SheetTitle>
          <SheetDescription>
            {t("What changed, and who changed it.")}
          </SheetDescription>
        </SheetHeader>
        <div className="px-4 pb-4">{children}</div>
      </SheetContent>
    </Sheet>
  );
}
