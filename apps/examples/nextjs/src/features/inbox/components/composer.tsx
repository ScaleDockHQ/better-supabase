"use client";

import { useAction } from "better-supabase/react";
import { SendIcon, StickyNoteIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useRef, useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { useErrorMessage } from "@/lib/use-error-message";

import { reply } from "../inbox-actions";

const TYPING_EVERY_MS = 2000;

/** Replies, or internal notes that only staff see. */
export function Composer({
  conversationId,
  onTyping,
  onSent,
}: {
  conversationId: string;
  onTyping: (typing: boolean) => void;
  onSent: () => Promise<void>;
}) {
  const t = useExtracted("inbox");
  const errorMessage = useErrorMessage();
  const bodyId = useId();
  const noteId = useId();
  const [body, setBody] = useState("");
  const [note, setNote] = useState(false);
  const lastPing = useRef(0);
  const send = useAction(reply, {
    onSuccess: () => {
      setBody("");
      onTyping(false);
      void onSent();
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <form
      className="space-y-2 border-t p-3"
      onSubmit={(event) => {
        event.preventDefault();
        if (body.trim() === "") return;
        void send.run({ conversationId, body, note });
      }}
    >
      <Label htmlFor={bodyId} className="sr-only">
        {note ? t("Note") : t("Reply")}
      </Label>
      <Textarea
        id={bodyId}
        value={body}
        rows={3}
        placeholder={
          note ? t("Write a note only staff see") : t("Write a reply")
        }
        className={note ? "bg-chart-4/10" : undefined}
        onChange={(event) => {
          setBody(event.target.value);
          if (event.timeStamp - lastPing.current > TYPING_EVERY_MS) {
            lastPing.current = event.timeStamp;
            onTyping(true);
          }
        }}
      />
      <div className="flex items-center gap-2">
        <Switch id={noteId} checked={note} onCheckedChange={setNote} />
        <Label htmlFor={noteId} className="text-sm font-normal">
          {t("Internal note")}
        </Label>
        <Button
          type="submit"
          size="sm"
          className="ml-auto"
          disabled={send.pending || body.trim() === ""}
        >
          {note ? <StickyNoteIcon /> : <SendIcon />}
          {note ? t("Add note") : t("Send")}
        </Button>
      </div>
    </form>
  );
}
