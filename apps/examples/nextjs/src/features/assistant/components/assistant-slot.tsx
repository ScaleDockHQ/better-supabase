"use client";

import { SparklesIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useEffect, useMemo, useState } from "react";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { usePathname } from "@/i18n/navigation";

import type { ModelOption } from "../assistant-queries";

import { loadAssistantSlot } from "../assistant-slot-actions";
import { pageContextOf } from "../page-context";
import { AssistantChatLazy } from "./assistant-chat-lazy";

interface Slot {
  readonly models: readonly ModelOption[];
  readonly durable: boolean;
}

/**
 * The assistant side panel. It opens over any page and shows which page it was
 * opened from; the models and the chat code load on the first open.
 */
export function AssistantSlot() {
  const t = useExtracted("assistant");
  const pathname = usePathname();
  const pageContext = useMemo(() => pageContextOf(pathname), [pathname]);
  const [open, setOpen] = useState(false);
  const [slot, setSlot] = useState<Slot | null>(null);
  const [chatId] = useState(() => crypto.randomUUID());

  useEffect(() => {
    if (!open || slot !== null) {
      return;
    }

    void loadAssistantSlot({}).then((result) => {
      if (result.ok) {
        setSlot(result.data);
      }
    });
  }, [open, slot]);

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger
        render={
          <Button variant="ghost" size="sm" aria-label={t("Assistant")}>
            <SparklesIcon />
            <span className="hidden sm:inline">{t("Assistant")}</span>
          </Button>
        }
      />
      <SheetContent className="flex flex-col gap-0 overflow-y-auto sm:max-w-xl">
        <SheetHeader className="border-b">
          <SheetTitle>{t("Assistant")}</SheetTitle>
          <SheetDescription className="flex items-center gap-2">
            {t("Opened from")}
            <Badge variant="outline">{pathname}</Badge>
            {pageContext.recordType === undefined ? null : (
              <Badge variant="secondary">{pageContext.recordType}</Badge>
            )}
          </SheetDescription>
        </SheetHeader>
        <div className="p-4">
          {slot === null ? (
            <Skeleton className="min-h-96 w-full rounded-xl" />
          ) : (
            <AssistantChatLazy
              id={chatId}
              messages={[]}
              durableAvailable={slot.durable}
              models={slot.models}
              pageContext={pageContext}
            />
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}
