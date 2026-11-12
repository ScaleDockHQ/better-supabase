"use client";

import { useAction } from "better-supabase/react";
import { RadioIcon } from "lucide-react";
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
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { toAppHref, useRouter } from "@/i18n/navigation";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { loadInboxes, simulateInbound } from "../inbox-actions";

/**
 * The simulator adapter: receive a message on any channel inbox as its
 * platform's webhook would deliver it, so the queue, the thread and the channel
 * rules (the WhatsApp window, delivery marks) can be tried without a Slack,
 * WhatsApp or email account. The same address on the same inbox continues one
 * thread.
 */
export function ChannelSimulator() {
  const t = useExtracted("inbox");
  const errorMessage = useErrorMessage();
  const router = useRouter();
  const ids = useId();
  const [open, setOpen] = useState(false);
  const [inboxId, setInboxId] = useState("");
  const [name, setName] = useState("Wile E. Coyote");
  const [address, setAddress] = useState("coyote@acme-roadrunner.test");
  const [subject, setSubject] = useState("");
  const [body, setBody] = useState("");

  const inboxes = useAction(loadInboxes);

  const receive = useAction(simulateInbound, {
    onSuccess: (conversationId) => {
      setOpen(false);
      setBody("");
      router.push(toAppHref(`/inbox/${conversationId}`));
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
            <RadioIcon />
            {t("Simulate a message")}
          </Button>
        }
      />
      <DialogContent>
        <form
          className="flex flex-col gap-4"
          onSubmit={(event) => {
            event.preventDefault();

            if (selected === "") {
              return;
            }

            void receive.run({
              inboxId: selected,
              name,
              address,
              subject,
              body,
            });
          }}
        >
          <DialogHeader>
            <DialogTitle>{t("Simulate an incoming message")}</DialogTitle>
            <DialogDescription>
              {t(
                "The message arrives as if the channel delivered it. The same address continues one conversation.",
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
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="flex flex-col gap-2">
              <Label htmlFor={`${ids}-name`}>{t("Name")}</Label>
              <Input
                id={`${ids}-name`}
                value={name}
                required
                onChange={(event) => {
                  setName(event.target.value);
                }}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor={`${ids}-address`}>
                {t("Email or phone number")}
              </Label>
              <Input
                id={`${ids}-address`}
                value={address}
                required
                onChange={(event) => {
                  setAddress(event.target.value);
                }}
              />
            </div>
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor={`${ids}-subject`}>{t("Subject")}</Label>
            <Input
              id={`${ids}-subject`}
              value={subject}
              onChange={(event) => {
                setSubject(event.target.value);
              }}
            />
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
            <Button
              type="submit"
              disabled={receive.pending || body.trim() === ""}
            >
              {t("Receive message")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
