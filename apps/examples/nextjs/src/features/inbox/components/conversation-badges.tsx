"use client";

import type { ReactNode } from "react";

import {
  GlobeIcon,
  MailIcon,
  MessageCircleIcon,
  MessagesSquareIcon,
  HashIcon,
  SmartphoneIcon,
} from "lucide-react";
import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

import type { ConversationRow, SlaState } from "../inbox-types";

function channelIcon(channel: string): ReactNode {
  switch (channel) {
    case "in_app": {
      return <GlobeIcon />;
    }

    case "email": {
      return <MailIcon />;
    }

    case "slack": {
      return <HashIcon />;
    }

    case "whatsapp": {
      return <MessageCircleIcon />;
    }

    case "sms": {
      return <SmartphoneIcon />;
    }

    default: {
      return <MessagesSquareIcon />;
    }
  }
}

/** The channel of a conversation: web widget, email, Slack, WhatsApp. */
export function ChannelBadge({
  channel,
}: {
  channel: ConversationRow["channel"];
}) {
  const t = useExtracted("inbox");

  if (channel === null) {
    return null;
  }

  const labels = {
    in_app: t("Web widget"),
    email: t("Email"),
    slack: t("Slack"),
    whatsapp: t("WhatsApp"),
    sms: t("SMS"),
  } as const;

  const label = Object.entries(labels).find(([key]) => key === channel)?.[1];

  return (
    <Badge variant="outline">
      {channelIcon(channel)}
      {label ?? channel}
    </Badge>
  );
}

/** The first response SLA: waiting, due soon, breached, or met. */
export function SlaBadge({ state }: { state: SlaState }) {
  const t = useExtracted("inbox");

  if (state === "ok" || state === "met") {
    return null;
  }

  return state === "breached" ? (
    <Badge variant="destructive-light">{t("SLA breached")}</Badge>
  ) : (
    <Badge variant="warning-light">{t("SLA due soon")}</Badge>
  );
}

export function StatusBadge({ row }: { row: ConversationRow }) {
  const t = useExtracted("inbox");

  switch (row.status) {
    case "resolved": {
      return <Badge variant="success-light">{t("Resolved")}</Badge>;
    }

    case "snoozed": {
      return <Badge variant="secondary">{t("Snoozed")}</Badge>;
    }

    case "pending": {
      return <Badge variant="warning-light">{t("Pending")}</Badge>;
    }

    case "open": {
      return <Badge variant="info-light">{t("Open")}</Badge>;
    }

    default: {
      const unreachable: never = row.status;

      return unreachable;
    }
  }
}
