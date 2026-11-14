"use client";

import { LifeBuoyIcon, SendIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useId, useRef, useState } from "react";

import { Bubble, BubbleContent, BubbleGroup } from "@/components/ui/bubble";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Marker, MarkerContent } from "@/components/ui/marker";
import {
  Message,
  MessageContent,
  MessageFooter,
} from "@/components/ui/message";
import {
  MessageScroller,
  MessageScrollerButton,
  MessageScrollerContent,
  MessageScrollerItem,
  MessageScrollerProvider,
  MessageScrollerViewport,
} from "@/components/ui/message-scroller";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { Textarea } from "@/components/ui/textarea";
import { useInboxWidget } from "@/hooks/use-inbox";
import { useAuth } from "@/lib/hooks";
import { toast } from "@/lib/toast";

import {
  askForHelp,
  loadMessage,
  loadThread,
  sendHelp,
} from "../inbox-actions";
import { unwrap } from "../inbox-load";

const TYPING_EVERY_MS = 2000;

/**
 * The customer side of the Help inbox: the assistant answers until staff take
 * over in /inbox.
 */
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
    get: async (messageId) => unwrap(await loadMessage({ messageId })),
  });

  const messages = widget.items ?? [];

  return (
    <>
      <MessageScrollerProvider autoScroll>
        <MessageScroller className="min-h-0 flex-1">
          <MessageScrollerViewport>
            <MessageScrollerContent className="gap-3 p-4">
              {messages.length === 0 ? (
                <Marker variant="separator">
                  <MarkerContent>
                    {t("No messages yet. Write below to start.")}
                  </MarkerContent>
                </Marker>
              ) : null}
              {messages.map((message) => {
                const mine = message.authorType === "contact";

                return (
                  <MessageScrollerItem
                    key={message.id}
                    messageId={message.id}
                    scrollAnchor={mine}
                  >
                    <Message align={mine ? "end" : "start"}>
                      <MessageContent>
                        <BubbleGroup>
                          <Bubble
                            align={mine ? "end" : "start"}
                            variant={mine ? "default" : "muted"}
                          >
                            <BubbleContent className="whitespace-pre-wrap">
                              {message.body}
                            </BubbleContent>
                          </Bubble>
                        </BubbleGroup>
                        <MessageFooter>
                          <span className="text-xs text-muted-foreground">
                            {format.dateTime(new Date(message.createdAt), {
                              timeStyle: "short",
                            })}
                          </span>
                        </MessageFooter>
                      </MessageContent>
                    </Message>
                  </MessageScrollerItem>
                );
              })}
            </MessageScrollerContent>
          </MessageScrollerViewport>
          <MessageScrollerButton />
        </MessageScroller>
      </MessageScrollerProvider>
      {widget.typing.length > 0 ? (
        <output className="block px-4 pb-2 text-xs text-muted-foreground">
          {t("Support is typing…")}
        </output>
      ) : null}
      <form
        className="space-y-2 border-t p-3"
        onSubmit={(event) => {
          event.preventDefault();
          const message = body.trim();

          if (message === "") {
            return;
          }

          setSending(true);
          void widget
            .submit(message)
            .then(() => {
              setBody("");
              widget.setTyping(false);

              return true;
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
