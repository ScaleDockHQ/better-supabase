"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { MegaphoneIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/lib/toast";

import { broadcast, loadInboxes } from "../inbox-actions";

/**
 * One message to every open conversation of a channel account, for an outage
 * notice or a policy change. WhatsApp conversations whose 24 hour window closed
 * are skipped, since they accept a template only.
 */
export function BroadcastDialog() {
  const t = useExtracted("inbox");
  const errorMessage = useErrorMessage();
  const ids = useId();
  const [open, setOpen] = useState(false);
  const [inboxId, setInboxId] = useState("");
  const [body, setBody] = useState("");

  const inboxes = useAction(loadInboxes);

  const send = useAction(broadcast, {
    onSuccess: ({ sent, skipped }) => {
      setOpen(false);
      setBody("");
      toast.success(
        t("Sent to {sent} conversations, skipped {skipped}", {
          sent: String(sent),
          skipped: String(skipped),
        }),
      );
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const items = (inboxes.data ?? []).map((inbox) => ({
    value: inbox.id,
    label: `${inbox.name} (${inbox.channel})`,
  }));

  const selected = inboxId === "" ? (items[0]?.value ?? "") : inboxId;

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);

        if (next) {
          void inboxes.run(undefined);
        }
      }}
    >
      <DialogTrigger
        render={
          <Button variant="outline" size="sm">
            <MegaphoneIcon />
            {t("Broadcast")}
          </Button>
        }
      />
      <DialogContent>
        <form
          className="flex flex-col gap-4"
          onSubmit={(event) => {
            event.preventDefault();

            if (selected !== "") {
              void send.run({ inboxId: selected, body });
            }
          }}
        >
          <DialogHeader>
            <DialogTitle>{t("Broadcast to open conversations")}</DialogTitle>
            <DialogDescription>
              {t(
                "Each open conversation of the channel gets this message as a reply, up to 50.",
              )}
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-2">
            <Label htmlFor={`${ids}-channel`}>{t("Channel")}</Label>
            <Select
              value={selected}
              items={items}
              onValueChange={(value) => {
                setInboxId(value ?? "");
              }}
            >
              <SelectTrigger id={`${ids}-channel`}>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {items.map((item) => (
                  <SelectItem key={item.value} value={item.value}>
                    {item.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor={`${ids}-body`}>{t("Message")}</Label>
            <Textarea
              id={`${ids}-body`}
              value={body}
              rows={4}
              required
              onChange={(event) => {
                setBody(event.target.value);
              }}
            />
          </div>
          <DialogFooter>
            <Button type="submit" disabled={send.pending || body.trim() === ""}>
              {t("Send broadcast")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
