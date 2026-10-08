"use client";

import { useInbox } from "better-supabase/blocks/inbox/react";
import { InboxIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useState } from "react";
import * as v from "valibot";

import { Badge } from "@/components/ui/badge";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { cn } from "@/lib/utils";

import { loadConversations } from "../inbox-actions";
import { unwrap } from "../inbox-load";
import {
  AssigneeFilter,
  type ConversationRow,
  ConversationStatus,
} from "../inbox-types";
import { ConversationPanel } from "./conversation-panel";

export function InboxView({
  organizationId,
  initial,
}: {
  organizationId: string;
  initial: readonly ConversationRow[];
}) {
  const t = useExtracted("inbox");
  const [status, setStatus] = useState<ConversationStatus>("open");
  const [assignee, setAssignee] = useState<AssigneeFilter>("anyone");
  const [selected, setSelected] = useState<string | null>(null);
  const assigneeItems = [
    { value: "anyone", label: t("Anyone") },
    { value: "me", label: t("Mine") },
    { value: "unassigned", label: t("Unassigned") },
  ] satisfies readonly { value: AssigneeFilter; label: string }[];

  return (
    <div className="grid min-h-128 gap-4 lg:grid-cols-3">
      <section aria-label={t("Conversations")} className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <Tabs
            value={status}
            onValueChange={(value) => {
              if (!v.is(ConversationStatus, value)) return;
              setStatus(value);
            }}
          >
            <TabsList>
              <TabsTrigger value="open">{t("Open")}</TabsTrigger>
              <TabsTrigger value="pending">{t("Pending")}</TabsTrigger>
              <TabsTrigger value="resolved">{t("Resolved")}</TabsTrigger>
              <TabsTrigger value="all">{t("All")}</TabsTrigger>
            </TabsList>
          </Tabs>
          <Select
            value={assignee}
            items={assigneeItems}
            onValueChange={(value) => {
              if (!v.is(AssigneeFilter, value)) return;
              setAssignee(value);
            }}
          >
            <SelectTrigger
              size="sm"
              className="w-32"
              aria-label={t("Assignee")}
            >
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {assigneeItems.map((item) => (
                <SelectItem key={item.value} value={item.value}>
                  {item.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <ConversationList
          key={`${status}:${assignee}`}
          organizationId={organizationId}
          status={status}
          assignee={assignee}
          initial={status === "open" && assignee === "anyone" ? initial : []}
          selected={selected}
          onSelect={setSelected}
        />
      </section>
      {selected === null ? (
        <Empty className="border lg:col-span-2">
          <EmptyHeader>
            <EmptyTitle>{t("Pick a conversation")}</EmptyTitle>
            <EmptyDescription>
              {t("Its messages, notes and actions show here.")}
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        <div className="lg:col-span-2">
          <ConversationPanel key={selected} conversationId={selected} />
        </div>
      )}
    </div>
  );
}

function ConversationList({
  organizationId,
  status,
  assignee,
  initial,
  selected,
  onSelect,
}: {
  organizationId: string;
  status: ConversationStatus;
  assignee: AssigneeFilter;
  initial: readonly ConversationRow[];
  selected: string | null;
  onSelect: (id: string) => void;
}) {
  const t = useExtracted("inbox");
  const format = useFormatter();
  const inbox = useInbox({
    organizationId,
    load: async () => unwrap(await loadConversations({ status, assignee })),
  });
  const conversations = inbox.items ?? initial;
  // Staff reads send no broadcast, so an opened conversation clears its badge here.
  const [openedAt, setOpenedAt] = useState<ReadonlyMap<string, number>>(
    () => new Map(),
  );
  const unread = (conversation: ConversationRow): boolean => {
    const opened = openedAt.get(conversation.id);
    return (
      conversation.unread &&
      (opened === undefined ||
        (conversation.lastMessageAt !== null &&
          Date.parse(conversation.lastMessageAt) > opened))
    );
  };
  return conversations.length === 0 ? (
    <Empty className="border">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <InboxIcon />
        </EmptyMedia>
        <EmptyTitle>{t("No conversations")}</EmptyTitle>
        <EmptyDescription>
          {t("Open Help in the header to start one as a customer.")}
        </EmptyDescription>
      </EmptyHeader>
    </Empty>
  ) : (
    <ul className="divide-y rounded-xl border">
      {conversations.map((conversation) => (
        <li key={conversation.id}>
          <button
            type="button"
            aria-current={selected === conversation.id ? "true" : undefined}
            className={cn(
              "hover:bg-muted/50 flex w-full flex-col gap-1 px-4 py-3 text-left text-sm",
              selected === conversation.id && "bg-muted",
            )}
            onClick={() => {
              setOpenedAt((current) =>
                new Map(current).set(conversation.id, Date.now()),
              );
              onSelect(conversation.id);
            }}
          >
            <span className="flex items-center gap-2">
              <span className="flex-1 truncate font-medium">
                {conversation.contactName || t("Visitor")}
              </span>
              {unread(conversation) ? <Badge>{t("New")}</Badge> : null}
            </span>
            <span className="truncate">
              {conversation.subject ?? t("No subject")}
            </span>
            <span className="text-muted-foreground flex gap-2 text-xs">
              <span className="flex-1 truncate">{conversation.preview}</span>
              {conversation.lastMessageAt ? (
                <span className="tabular-nums">
                  {format.dateTime(new Date(conversation.lastMessageAt), {
                    dateStyle: "short",
                    timeStyle: "short",
                  })}
                </span>
              ) : null}
            </span>
          </button>
        </li>
      ))}
    </ul>
  );
}
