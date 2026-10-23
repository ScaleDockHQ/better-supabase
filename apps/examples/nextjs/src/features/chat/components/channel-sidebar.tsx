// #region recipe:channel-sidebar
"use client";

import type { SubmitEvent } from "react";

import { useAction } from "better-supabase/react";
import {
  HashIcon,
  LockIcon,
  PlusIcon,
  RotateCwIcon,
  SearchIcon,
} from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Alert, AlertAction, AlertTitle } from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import {
  Field,
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { useConversations } from "@/hooks/use-messaging";
import { useErrorMessage } from "@/lib/use-error-message";
import { cn } from "@/lib/utils";

import type { ChannelRow } from "../chat-actions";

import { browseChannels, createChannel, joinChannel } from "../chat-actions";

export interface OpenChannel {
  readonly id: string;
  readonly name: string;
}

const KINDS = ["channel"] as const;

/**
 * The caller's channels with unread and mention counts, kept live over
 * Realtime, plus dialogs to browse the organization's channels and create one.
 */
export function ChannelSidebar({
  selected,
  onSelect,
}: {
  selected: string | null;
  onSelect: (channel: OpenChannel) => void;
}) {
  const t = useExtracted("chat");
  const errorMessage = useErrorMessage();
  const { conversations, error, refresh } = useConversations({ kinds: KINDS });

  const opened = (channel: OpenChannel) => {
    void refresh();
    onSelect(channel);
  };

  return (
    <Card size="sm" className="min-h-0">
      <CardHeader>
        <CardTitle>{t("Channels")}</CardTitle>
        <CardAction className="flex gap-1">
          <BrowseChannelsDialog onOpened={opened} />
          <CreateChannelDialog onCreated={opened} />
        </CardAction>
      </CardHeader>
      <CardContent className="flex min-h-0 flex-1 flex-col gap-3">
        {error ? (
          <Alert variant="destructive" aria-live="polite">
            <AlertTitle>{errorMessage(error)}</AlertTitle>
            <AlertAction>
              <Button
                type="button"
                size="sm"
                variant="outline"
                onClick={() => void refresh()}
              >
                <RotateCwIcon aria-hidden />
                {t("Retry")}
              </Button>
            </AlertAction>
          </Alert>
        ) : null}
        {conversations === undefined ? (
          <div
            className="flex flex-col gap-2"
            aria-busy="true"
            aria-live="polite"
          >
            <span className="sr-only">{t("Loading channels")}</span>
            <Skeleton className="h-8" />
            <Skeleton className="h-8" />
            <Skeleton className="h-8" />
          </div>
        ) : conversations.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <HashIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No channels yet")}</EmptyTitle>
              <EmptyDescription>
                {t("Create one, or browse the channels others made.")}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <ScrollArea className="min-h-0 flex-1">
            <ul className="flex flex-col gap-0.5" data-testid="channels">
              {conversations.map((conversation) => {
                const name = conversation.title ?? conversation.id;
                const current = selected === conversation.id;

                return (
                  <li key={conversation.id}>
                    <Button
                      type="button"
                      variant={current ? "secondary" : "ghost"}
                      size="sm"
                      className="w-full justify-start"
                      aria-current={current ? "true" : undefined}
                      onClick={() => {
                        onSelect({ id: conversation.id, name });
                      }}
                    >
                      {conversation.access === "members" ? (
                        <LockIcon aria-hidden />
                      ) : (
                        <HashIcon aria-hidden />
                      )}
                      <span
                        className={cn(
                          "truncate",
                          conversation.unread > 0 && "font-semibold",
                        )}
                      >
                        {name}
                      </span>
                      {conversation.mentions > 0 ? (
                        <Badge variant="destructive" className="ml-auto">
                          @{conversation.mentions}
                        </Badge>
                      ) : conversation.unread > 0 ? (
                        <Badge variant="secondary" className="ml-auto">
                          {conversation.unread}
                        </Badge>
                      ) : null}
                    </Button>
                  </li>
                );
              })}
            </ul>
          </ScrollArea>
        )}
      </CardContent>
    </Card>
  );
}

function BrowseChannelsDialog({
  onOpened,
}: {
  onOpened: (channel: OpenChannel) => void;
}) {
  const t = useExtracted("chat");
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const browse = useAction(browseChannels);
  const join = useAction(joinChannel);

  const pick = async (channel: ChannelRow) => {
    if (!channel.joined) {
      const joined = await join.run({ channelId: channel.id });

      if (!joined.ok) {
        toast.error(errorMessage(joined.error));

        return;
      }
    }

    setOpen(false);
    onOpened({ id: channel.id, name: channel.name });
  };

  const rows = browse.data;

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);

        if (next) {
          void browse.run({});
        }
      }}
    >
      <DialogTrigger
        render={
          <Button
            size="icon-sm"
            variant="outline"
            aria-label={t("Browse channels")}
          />
        }
      >
        <SearchIcon aria-hidden />
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("Browse channels")}</DialogTitle>
          <DialogDescription>
            {t("Every public channel, and the private ones you are in.")}
          </DialogDescription>
        </DialogHeader>
        {browse.error ? (
          <Alert variant="destructive" aria-live="polite">
            <AlertTitle>{errorMessage(browse.error)}</AlertTitle>
            <AlertAction>
              <Button
                type="button"
                size="sm"
                variant="outline"
                onClick={() => void browse.run({})}
              >
                <RotateCwIcon aria-hidden />
                {t("Retry")}
              </Button>
            </AlertAction>
          </Alert>
        ) : rows === undefined ? (
          <div
            className="flex flex-col gap-2"
            aria-busy="true"
            aria-live="polite"
          >
            <span className="sr-only">{t("Loading channels")}</span>
            <Skeleton className="h-10" />
            <Skeleton className="h-10" />
          </div>
        ) : rows.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyTitle>{t("No channels to join")}</EmptyTitle>
              <EmptyDescription>
                {t("Close this and create the first one.")}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <ul className="flex flex-col gap-2">
            {rows.map((channel) => (
              <li key={channel.id} className="flex items-center gap-3">
                <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                  <span className="flex items-center gap-1 text-sm font-medium">
                    {channel.visibility === "private" ? (
                      <LockIcon aria-hidden className="size-3.5" />
                    ) : (
                      <HashIcon aria-hidden className="size-3.5" />
                    )}
                    <span className="truncate">{channel.name}</span>
                  </span>
                  <span className="truncate text-xs text-muted-foreground">
                    {channel.topic ??
                      t("{count, plural, one {# member} other {# members}}", {
                        count: channel.memberCount,
                      })}
                  </span>
                </div>
                <Button
                  type="button"
                  size="sm"
                  variant={channel.joined ? "outline" : "default"}
                  disabled={join.pending}
                  onClick={() => void pick(channel)}
                >
                  {channel.joined ? t("Open") : t("Join")}
                </Button>
              </li>
            ))}
          </ul>
        )}
      </DialogContent>
    </Dialog>
  );
}

function CreateChannelDialog({
  onCreated,
}: {
  onCreated: (channel: OpenChannel) => void;
}) {
  const t = useExtracted("chat");
  const errorMessage = useErrorMessage();
  const fieldId = useId();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [topic, setTopic] = useState("");
  const [isPrivate, setPrivate] = useState(false);

  const create = useAction(createChannel, {
    onSuccess: (id) => {
      setOpen(false);
      onCreated({ id, name: name.trim().toLowerCase() });
    },
  });

  const message =
    create.error === undefined ? null : errorMessage(create.error);

  const submit = (event: SubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    void create.run({
      name,
      topic,
      visibility: isPrivate ? "private" : "public",
    });
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        setName("");
        setTopic("");
        setPrivate(false);
        create.reset();
      }}
    >
      <DialogTrigger
        render={<Button size="icon-sm" aria-label={t("Create a channel")} />}
      >
        <PlusIcon aria-hidden />
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={submit} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Create a channel")}</DialogTitle>
            <DialogDescription>
              {t("A place for one team, project or topic.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={message ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-name`}>{t("Name")}</FieldLabel>
              <Input
                id={`${fieldId}-name`}
                value={name}
                onChange={(event) => {
                  setName(event.target.value);
                }}
                required
                maxLength={80}
                pattern="[A-Za-z0-9][A-Za-z0-9_\-]*"
                placeholder="launch"
              />
              <FieldDescription>
                {t("Lowercase letters, digits, - and _.")}
              </FieldDescription>
              {message ? <FieldError>{message}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-topic`}>{t("Topic")}</FieldLabel>
              <Input
                id={`${fieldId}-topic`}
                value={topic}
                onChange={(event) => {
                  setTopic(event.target.value);
                }}
                maxLength={250}
              />
            </Field>
            <div className="flex items-center gap-2">
              <Switch
                id={`${fieldId}-private`}
                checked={isPrivate}
                onCheckedChange={setPrivate}
              />
              <Label
                htmlFor={`${fieldId}-private`}
                className="text-sm font-normal"
              >
                {t("Private: only the people you add see it")}
              </Label>
            </div>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={create.pending}>
              {t("Create")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
// #endregion recipe:channel-sidebar
