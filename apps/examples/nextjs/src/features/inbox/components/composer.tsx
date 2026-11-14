"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import {
  BookmarkIcon,
  AtSignIcon,
  ClockIcon,
  SendIcon,
  SparklesIcon,
  StickyNoteIcon,
  TriangleAlertIcon,
} from "lucide-react";
import { useExtracted } from "next-intl";
import { useEffect, useEffectEvent, useId, useRef, useState } from "react";

import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Item,
  ItemActions,
  ItemContent,
  ItemDescription,
  ItemTitle,
} from "@/components/ui/item";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { loadMembers } from "@/features/organization/organization-actions";
import { toast } from "@/lib/toast";

import type { ConversationRow, Later } from "../inbox-types";

import {
  discardDraft,
  loadDrafts,
  loadMacros,
  reply,
  saveDraft,
  scheduleReply,
  sendDraft,
} from "../inbox-actions";
import { LaterItems } from "./later-items";

const TYPING_EVERY_MS = 2000;

/**
 * Replies, replies sent later, internal notes, macros, and the drafts: the
 * caller's own comes back after a reload, and the AI drafts for the team wait
 * above the text box until someone uses or discards them. On WhatsApp, a
 * conversation whose 24 hour window closed accepts a template only.
 */
export function Composer({
  conversationId,
  channel,
  windowOpen,
  onTyping,
  onSent,
  onScheduled,
}: {
  conversationId: string;
  channel: ConversationRow["channel"];
  windowOpen: boolean;
  onTyping: (typing: boolean) => void;
  onSent: () => Promise<void>;
  onScheduled: () => void;
}) {
  const t = useExtracted("inbox");
  const errorMessage = useErrorMessage();
  const bodyId = useId();
  const noteId = useId();
  const [body, setBody] = useState("");
  const [note, setNote] = useState(false);
  // Read only when the note is sent, so a pick doesn't redraw the form.
  const mentioned = useRef(new Map<string, string>());
  const lastPing = useRef(0);

  const onError = (error: Parameters<typeof errorMessage>[0]) => {
    toast.error(errorMessage(error));
  };

  const drafts = useAction(loadDrafts);
  const macros = useAction(loadMacros);
  const members = useAction(loadMembers);

  const loadAll = useEffectEvent((id: string) => {
    void drafts.run({ conversationId: id }).then((result) => {
      const own = result.ok
        ? result.data.find((draft) => draft.source === "user")
        : undefined;

      if (own) {
        setBody((current) => (current === "" ? own.body : current));
        setNote(own.kind === "note");
      }
    });
    void macros.run(undefined);
    void members.run(undefined);
  });

  useEffect(() => {
    loadAll(conversationId);
  }, [conversationId]);

  const reload = () => {
    void drafts.run({ conversationId });
  };

  const send = useAction(reply, {
    onSuccess: () => {
      setBody("");
      mentioned.current.clear();
      onTyping(false);
      void onSent();
    },
    onError,
  });

  const draft = useAction(saveDraft);

  const later = useAction(scheduleReply, {
    onSuccess: () => {
      setBody("");
      onTyping(false);
      onScheduled();
      toast.success(t("Reply scheduled"));
    },
    onError,
  });

  const sendSuggestion = useAction(sendDraft, {
    onSuccess: () => {
      reload();
      void onSent();
    },
    onError,
  });

  const discard = useAction(discardDraft, { onSuccess: reload, onError });

  const empty = body.trim() === "";
  const busy = send.pending || later.pending || sendSuggestion.pending;
  const locked = !windowOpen && !note;

  const suggestions = (drafts.data ?? []).filter(
    (item) => item.source === "ai",
  );

  const available = (macros.data ?? []).filter(
    (macro) => macro.channel === channel || channel === null,
  );

  return (
    <form
      className="flex flex-col gap-2 border-t p-3"
      onSubmit={(event) => {
        event.preventDefault();

        if (empty || locked) {
          return;
        }

        void send.run({
          conversationId,
          body,
          note,
          mentions: [...mentioned.current]
            .filter(([, name]) => body.includes(`@${name}`))
            .map(([id]) => id),
        });
      }}
    >
      {suggestions.map((suggestion) => (
        <Item key={suggestion.id} variant="outline" size="sm">
          <SparklesIcon aria-hidden />
          <ItemContent>
            <ItemTitle>{t("AI draft for the team")}</ItemTitle>
            <ItemDescription className="whitespace-pre-wrap">
              {suggestion.body}
            </ItemDescription>
          </ItemContent>
          <ItemActions>
            <Button
              type="button"
              size="sm"
              variant="outline"
              onClick={() => {
                setBody(suggestion.body);
                setNote(false);
              }}
            >
              {t("Edit")}
            </Button>
            <Button
              type="button"
              size="sm"
              disabled={busy}
              onClick={() => {
                void sendSuggestion.run({
                  draftId: suggestion.id,
                  body: suggestion.body,
                });
              }}
            >
              {t("Send")}
            </Button>
            <Button
              type="button"
              size="sm"
              variant="ghost"
              onClick={() => {
                void discard.run({ draftId: suggestion.id });
              }}
            >
              {t("Discard")}
            </Button>
          </ItemActions>
        </Item>
      ))}
      {locked ? (
        <Alert variant="warning">
          <TriangleAlertIcon />
          <AlertTitle>{t("The WhatsApp reply window is closed")}</AlertTitle>
          <AlertDescription>
            {t(
              "The contact wrote more than 24 hours ago. Send an approved template, or add an internal note.",
            )}
          </AlertDescription>
        </Alert>
      ) : null}
      <Label htmlFor={bodyId} className="sr-only">
        {note ? t("Note") : t("Reply")}
      </Label>
      <Textarea
        id={bodyId}
        value={body}
        rows={3}
        disabled={locked}
        placeholder={
          note ? t("Write a note only staff see") : t("Write a reply")
        }
        className={note ? "bg-chart-4/10" : undefined}
        onBlur={() => {
          if (!empty && !locked) {
            void draft.run({ conversationId, body, note });
          }
        }}
        onChange={(event) => {
          setBody(event.target.value);

          if (event.timeStamp - lastPing.current > TYPING_EVERY_MS) {
            lastPing.current = event.timeStamp;
            onTyping(true);
          }
        }}
      />
      <div className="flex flex-wrap items-center gap-2">
        <Switch id={noteId} checked={note} onCheckedChange={setNote} />
        <Label htmlFor={noteId} className="text-sm font-normal">
          {t("Internal note")}
        </Label>
        <DropdownMenu>
          <DropdownMenuTrigger
            disabled={busy || available.length === 0}
            render={
              <Button
                type="button"
                size="sm"
                variant="outline"
                className="ml-auto"
              />
            }
          >
            <BookmarkIcon />
            {windowOpen ? t("Macros") : t("Templates")}
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-64">
            <DropdownMenuGroup>
              <DropdownMenuLabel>
                {windowOpen ? t("Insert a macro") : t("Send a template")}
              </DropdownMenuLabel>
              {available.map((macro) => (
                <DropdownMenuItem
                  key={macro.id}
                  onClick={() => {
                    if (windowOpen) {
                      setBody(macro.body);
                      setNote(false);

                      return;
                    }

                    void send.run({
                      conversationId,
                      body: macro.body,
                      note: false,
                    });
                  }}
                >
                  {macro.name}
                </DropdownMenuItem>
              ))}
            </DropdownMenuGroup>
          </DropdownMenuContent>
        </DropdownMenu>
        {note ? (
          <DropdownMenu>
            <DropdownMenuTrigger
              disabled={busy || (members.data ?? []).length === 0}
              render={<Button type="button" size="sm" variant="outline" />}
            >
              <AtSignIcon />
              {t("Mention")}
            </DropdownMenuTrigger>
            <DropdownMenuContent align="start" className="w-64">
              <DropdownMenuGroup>
                <DropdownMenuLabel>{t("Notify a teammate")}</DropdownMenuLabel>
                {(members.data ?? []).map((member) => {
                  const name = member.name ?? member.email ?? t("Teammate");

                  return (
                    <DropdownMenuItem
                      key={member.userId}
                      onClick={() => {
                        setBody((current) => `${current}@${name} `);
                        mentioned.current.set(member.userId, name);
                      }}
                    >
                      {name}
                    </DropdownMenuItem>
                  );
                })}
              </DropdownMenuGroup>
            </DropdownMenuContent>
          </DropdownMenu>
        ) : null}
        {note || locked ? null : (
          <DropdownMenu>
            <DropdownMenuTrigger
              disabled={busy || empty}
              render={<Button type="button" size="sm" variant="outline" />}
            >
              <ClockIcon />
              {t("Send later")}
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <LaterItems
                onSelect={(at: Later) => {
                  void later.run({ conversationId, body, at });
                }}
              />
            </DropdownMenuContent>
          </DropdownMenu>
        )}
        <Button type="submit" size="sm" disabled={busy || empty || locked}>
          {note ? <StickyNoteIcon /> : <SendIcon />}
          {note ? t("Add note") : t("Send")}
        </Button>
      </div>
    </form>
  );
}
