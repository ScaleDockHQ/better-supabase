// #region recipe:inbox-threads
"use client";

import { useAction } from "better-supabase/react";
import { InboxIcon, SearchIcon } from "lucide-react";
import { useExtracted, useFormatter, useNow } from "next-intl";
import { useParams } from "next/navigation";
import {
  debounce,
  parseAsString,
  parseAsStringLiteral,
  useQueryStates,
} from "nuqs";
import { useEffect, useEffectEvent, useState } from "react";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { useInbox } from "@/hooks/use-inbox";
import { Link, toAppHref } from "@/i18n/navigation";
import { cn } from "@/lib/utils";

import type { ConversationRow, InboxSummary } from "../inbox-types";

import { loadConversations, loadInboxes } from "../inbox-actions";
import { unwrap } from "../inbox-load";
import { QUEUE_ASSIGNEES, QUEUE_STATUSES, slaStateOf } from "../inbox-types";
import { ChannelBadge, SlaBadge } from "./conversation-badges";

const ALL_CHANNELS = "all";

const queueParsers = {
  q: parseAsString.withDefault(""),
  status: parseAsStringLiteral(QUEUE_STATUSES).withDefault("open"),
  assignee: parseAsStringLiteral(QUEUE_ASSIGNEES).withDefault("anyone"),
  channel: parseAsString.withDefault(""),
};

/**
 * The conversation queue: search, status, assignee and channel run in the
 * database (`loadConversations`), the filters live in the URL, and Realtime
 * pings reload the list without refetching the page. A row links to
 * `/inbox/<id>` and keeps the filters, so the thread opens beside the queue.
 */
export function ConversationQueue({
  organizationId,
  initial,
}: {
  organizationId: string;
  initial: readonly ConversationRow[];
}) {
  const t = useExtracted("inbox");

  const [filters, setFilters] = useQueryStates(queueParsers, {
    limitUrlUpdates: debounce(300),
  });

  const inboxes = useAction(loadInboxes);

  const loadChannels = useEffectEvent(() => {
    void inboxes.run(undefined);
  });

  useEffect(() => {
    loadChannels();
  }, []);

  const channelItems = [
    { value: ALL_CHANNELS, label: t("All channels") },
    ...(inboxes.data ?? []).map((inbox: InboxSummary) => ({
      value: inbox.id,
      label: inbox.name,
    })),
  ];

  const statusItems = [
    { value: "open", label: t("Open") },
    { value: "pending", label: t("Pending") },
    { value: "snoozed", label: t("Snoozed") },
    { value: "resolved", label: t("Resolved") },
    { value: "all", label: t("All statuses") },
  ];

  const assigneeItems = [
    { value: "anyone", label: t("Anyone") },
    { value: "me", label: t("Mine") },
    { value: "unassigned", label: t("Unassigned") },
  ];

  const isDefault =
    filters.status === "open" &&
    filters.assignee === "anyone" &&
    filters.channel === "" &&
    filters.q === "";

  return (
    <section
      aria-label={t("Conversations")}
      className="flex h-full min-h-0 flex-col gap-3 p-3"
    >
      <div className="relative">
        <SearchIcon
          aria-hidden
          className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground"
        />
        <Input
          type="search"
          value={filters.q}
          placeholder={t("Search conversations")}
          aria-label={t("Search conversations")}
          className="pl-8"
          onChange={(event) => {
            void setFilters({ q: event.target.value });
          }}
        />
      </div>
      <div className="grid grid-cols-2 gap-2">
        <Select
          value={filters.status}
          items={statusItems}
          onValueChange={(value) => {
            const status = QUEUE_STATUSES.find((item) => item === value);

            if (status !== undefined) {
              void setFilters({ status });
            }
          }}
        >
          <SelectTrigger size="sm" className="w-full" aria-label={t("Status")}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {statusItems.map((item) => (
              <SelectItem key={item.value} value={item.value}>
                {item.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Select
          value={filters.assignee}
          items={assigneeItems}
          onValueChange={(value) => {
            const assignee = QUEUE_ASSIGNEES.find((item) => item === value);

            if (assignee !== undefined) {
              void setFilters({ assignee });
            }
          }}
        >
          <SelectTrigger
            size="sm"
            className="flex-1"
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
        <Select
          value={filters.channel === "" ? ALL_CHANNELS : filters.channel}
          items={channelItems}
          onValueChange={(value) => {
            void setFilters({
              channel: value === null || value === ALL_CHANNELS ? "" : value,
            });
          }}
        >
          <SelectTrigger
            size="sm"
            className="col-span-2 w-full"
            aria-label={t("Channel")}
          >
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {channelItems.map((item) => (
              <SelectItem key={item.value} value={item.value}>
                {item.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      <QueueRows
        key={`${filters.status}:${filters.assignee}:${filters.channel}:${filters.q}`}
        organizationId={organizationId}
        status={filters.status}
        assignee={filters.assignee}
        channel={filters.channel}
        q={filters.q}
        initial={isDefault ? initial : null}
        onClear={() => {
          void setFilters({
            q: "",
            status: "open",
            assignee: "anyone",
            channel: "",
          });
        }}
      />
    </section>
  );
}

const PAGE_SIZE = 40;

function QueueRows({
  organizationId,
  status,
  assignee,
  channel,
  q,
  initial,
  onClear,
}: {
  organizationId: string;
  status: ConversationRow["status"] | "all";
  assignee: (typeof QUEUE_ASSIGNEES)[number];
  channel: string;
  q: string;
  initial: readonly ConversationRow[] | null;
  onClear: () => void;
}) {
  const t = useExtracted("inbox");
  const format = useFormatter();
  const selected = useParams<{ conversation?: string }>().conversation;
  const [search] = useQueryStates(queueParsers);
  const [more, setMore] = useState<readonly ConversationRow[]>([]);
  const nowDate = useNow({ updateInterval: 60_000 });
  const now = nowDate.getTime();

  const inbox = useInbox({
    organizationId,
    load: async () =>
      unwrap(await loadConversations({ status, assignee, channel, q })),
  });

  const next = useAction(loadConversations);

  const first = inbox.items ?? initial;

  if (first === null) {
    return inbox.error === undefined || inbox.error === null ? (
      <QueueSkeleton />
    ) : (
      <Empty className="border">
        <EmptyHeader>
          <EmptyTitle>{t("The queue did not load")}</EmptyTitle>
          <EmptyDescription>
            {inbox.error instanceof Error
              ? inbox.error.message
              : t("Check your connection and try again.")}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <Button
            variant="outline"
            size="sm"
            onClick={() => {
              void inbox.refresh();
            }}
          >
            {t("Retry")}
          </Button>
        </EmptyContent>
      </Empty>
    );
  }

  const rows = [...first, ...more];
  const last = rows.at(-1);
  const hasMore = first.length >= PAGE_SIZE && more.length % PAGE_SIZE === 0;

  const query = new URLSearchParams();

  if (search.q !== "") {
    query.set("q", search.q);
  }

  if (search.status !== "open") {
    query.set("status", search.status);
  }

  if (search.assignee !== "anyone") {
    query.set("assignee", search.assignee);
  }

  if (search.channel !== "") {
    query.set("channel", search.channel);
  }

  const suffix = query.size === 0 ? "" : `?${query.toString()}`;

  if (rows.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <InboxIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No conversations")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Nothing matches these filters. Clear them, or use the simulator to receive a message.",
            )}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <Button variant="outline" size="sm" onClick={onClear}>
            {t("Clear filters")}
          </Button>
        </EmptyContent>
      </Empty>
    );
  }

  return (
    <ul className="-mx-3 min-h-0 flex-1 divide-y overflow-y-auto border-y">
      {rows.map((conversation) => {
        const sla = slaStateOf(conversation, now);

        return (
          <li key={conversation.id}>
            <Link
              href={toAppHref(`/inbox/${conversation.id}${suffix}`)}
              aria-current={selected === conversation.id ? "page" : undefined}
              prefetch={false}
              className={cn(
                "flex flex-col gap-1 px-3 py-3 text-sm transition-colors hover:bg-muted/50",
                selected === conversation.id && "bg-muted",
              )}
            >
              <span className="flex items-center gap-2">
                <span
                  className={cn(
                    "flex-1 truncate",
                    conversation.unread ? "font-semibold" : "font-medium",
                  )}
                >
                  {conversation.contactName || t("Visitor")}
                </span>
                {conversation.unread ? (
                  <Badge variant="primary-light">{t("New")}</Badge>
                ) : null}
                {conversation.lastMessageAt ? (
                  <span className="text-xs text-muted-foreground tabular-nums">
                    {format.relativeTime(
                      new Date(conversation.lastMessageAt),
                      now,
                    )}
                  </span>
                ) : null}
              </span>
              <span className="truncate">
                {conversation.subject ?? t("No subject")}
              </span>
              <span className="truncate text-xs text-muted-foreground">
                {conversation.preview}
              </span>
              <span className="flex flex-wrap items-center gap-1">
                <ChannelBadge channel={conversation.channel} />
                <SlaBadge state={sla} />
                {conversation.assigneeId === null ? (
                  <Badge variant="secondary">{t("Unassigned")}</Badge>
                ) : null}
                {conversation.botMode === "bot" ? (
                  <Badge variant="secondary">{t("Bot")}</Badge>
                ) : null}
              </span>
            </Link>
          </li>
        );
      })}
      {hasMore && last ? (
        <li className="p-3">
          <Button
            variant="outline"
            size="sm"
            className="w-full"
            disabled={next.pending}
            onClick={() => {
              void next
                .run({
                  status,
                  assignee,
                  channel,
                  q,
                  cursor: { id: last.id, lastMessageAt: last.lastMessageAt },
                })
                .then((result) => {
                  if (result.ok) {
                    setMore((current) => [...current, ...result.data]);
                  }
                });
            }}
          >
            {t("Load more")}
          </Button>
        </li>
      ) : null}
    </ul>
  );
}

export function QueueSkeleton() {
  return (
    <div className="flex flex-col gap-2" aria-busy="true">
      {Array.from({ length: 6 }, (_, index) => (
        <Skeleton key={index} className="h-20 w-full" />
      ))}
    </div>
  );
}
// #endregion recipe:inbox-threads
