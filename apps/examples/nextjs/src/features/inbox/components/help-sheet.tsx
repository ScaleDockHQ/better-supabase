"use client";

import { useInboxWidget } from "better-supabase/blocks/inbox/react";
import { LifeBuoyIcon, SendIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useId, useRef, useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { Textarea } from "@/components/ui/textarea";
import { useAuth } from "@/lib/hooks";
import { cn } from "@/lib/utils";

import { askForHelp, loadThread, sendHelp } from "../inbox-actions";
import { unwrap } from "../inbox-load";

const TYPING_EVERY_MS = 2000;

/** The customer side of the Help inbox: the assistant answers until staff take over in /inbox. */
export function HelpSheet() {
  const t = useExtracted("inbox");
  const [open, setOpen] = useState(false);
  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger
        render={
          <Button variant="ghost" size="sm" aria-label={t("Help")}>
            <LifeBuoyIcon />
            <span className="hidden sm:inline">{t("Help")}</span>
          </Button>
        }
      />
      <SheetContent className="flex flex-col gap-0 p-0">
        <SheetHeader className="border-b">
          <SheetTitle>{t("Help")}</SheetTitle>
          <SheetDescription>
            {t(
              "Ask a question. The assistant answers first, and Acme's support team can take over.",
            )}
          </SheetDescription>
        </SheetHeader>
        {open ? <HelpChat /> : null}
      </SheetContent>
    </Sheet>
  );
}

function HelpChat() {
  const t = useExtracted("inbox");
  const format = useFormatter();
  const bodyId = useId();
  const userId = useAuth().user?.id ?? "anonymous";
  const [body, setBody] = useState("");
  const [sending, setSending] = useState(false);
  const lastPing = useRef(0);
  const widget = useInboxWidget({
    storageKey: `acme:help:${userId}`,
    open: async (message) => unwrap(await askForHelp({ message })),
    send: async (conversationId, message) => {
      unwrap(await sendHelp({ conversationId, message }));
    },
    load: async (conversationId) =>
      unwrap(await loadThread({ conversationId })).messages,
  });
  const messages = widget.items ?? [];

  return (
    <>
      <ol className="flex-1 space-y-3 overflow-y-auto p-4">
        {messages.length === 0 ? (
          <li className="text-muted-foreground text-sm">
            {t("No messages yet. Write below to start.")}
          </li>
        ) : null}
        {messages.map((message) => {
          const mine = message.authorType === "contact";
          return (
            <li
              key={message.id}
              className={cn(
                "flex flex-col gap-1",
                mine ? "items-end" : "items-start",
              )}
            >
              <div
                className={cn(
                  "max-w-4/5 rounded-lg px-3 py-2 text-sm whitespace-pre-wrap",
                  mine ? "bg-primary text-primary-foreground" : "bg-muted",
                )}
              >
                {message.body}
              </div>
              <span className="text-muted-foreground text-xs">
                {format.dateTime(new Date(message.createdAt), {
                  timeStyle: "short",
                })}
              </span>
            </li>
          );
        })}
      </ol>
      {widget.typing.length > 0 ? (
        <output className="text-muted-foreground block px-4 pb-2 text-xs">
          {t("Support is typing…")}
        </output>
      ) : null}
      <form
        className="space-y-2 border-t p-3"
        onSubmit={(event) => {
          event.preventDefault();
          const message = body.trim();
          if (message === "") return;
          setSending(true);
          widget
            .submit(message)
            .then(() => {
              setBody("");
              widget.setTyping(false);
            })
            .catch(() => {
              toast.error(t("Could not send"));
            })
            .finally(() => {
              setSending(false);
            });
        }}
      >
        <Label htmlFor={bodyId} className="sr-only">
          {t("Message")}
        </Label>
        <Textarea
          id={bodyId}
          rows={3}
          value={body}
          placeholder={t("How can we help?")}
          onChange={(event) => {
            setBody(event.target.value);
            if (
              widget.conversationId !== null &&
              event.timeStamp - lastPing.current > TYPING_EVERY_MS
            ) {
              lastPing.current = event.timeStamp;
              widget.setTyping(true);
            }
          }}
        />
        <div className="flex items-center justify-between gap-2">
          {widget.conversationId === null ? (
            <span />
          ) : (
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={() => {
                widget.reset();
              }}
            >
              {t("New conversation")}
            </Button>
          )}
          <Button
            type="submit"
            size="sm"
            disabled={sending || body.trim() === ""}
          >
            <SendIcon />
            {t("Send")}
          </Button>
        </div>
      </form>
    </>
  );
}
