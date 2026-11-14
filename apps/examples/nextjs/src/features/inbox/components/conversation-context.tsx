import { useExtracted, useFormatter } from "next-intl";

import { Badge } from "@/components/reui/badge";
import {
  Item,
  ItemContent,
  ItemDescription,
  ItemGroup,
  ItemTitle,
} from "@/components/ui/item";
import { Link, toAppHref } from "@/i18n/navigation";

import type { ConversationContext } from "../inbox-queries";

import { FIRST_RESPONSE_TARGET_MINUTES } from "../inbox-types";
import { ContactDeals } from "./contact-deals";

/**
 * The right pane of a conversation: the contact, the conversation's own facts
 * (channel account, priority, first response against the SLA target), the open
 * deals that name the contact (an inbox contact is a CRM person) and the
 * contact's earlier conversations. The contact's name opens the CRM person.
 * Orders have no link to a person yet.
 */
export function ConversationContextPanel({
  context,
}: {
  context: ConversationContext;
}) {
  const t = useExtracted("inbox");
  const format = useFormatter();
  const { conversation, history } = context;

  const facts: readonly { label: string; value: string }[] = [
    { label: t("Email"), value: conversation.contactEmail ?? "-" },
    { label: t("Phone"), value: conversation.contactPhone ?? "-" },
    { label: t("Channel account"), value: conversation.inboxName ?? "-" },
    { label: t("Priority"), value: conversation.priority },
    {
      label: t("First response"),
      value:
        conversation.firstResponseAt === null
          ? t("Waiting (target {minutes} min)", {
              minutes: String(FIRST_RESPONSE_TARGET_MINUTES),
            })
          : format.dateTime(new Date(conversation.firstResponseAt), {
              dateStyle: "short",
              timeStyle: "short",
            }),
    },
    {
      label: t("Started"),
      value: format.dateTime(new Date(conversation.createdAt), {
        dateStyle: "medium",
      }),
    },
  ];

  return (
    <aside
      aria-label={t("Contact")}
      className="flex h-full min-h-0 flex-col gap-6 overflow-y-auto p-4"
    >
      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-medium">
          <Link
            href={toAppHref(`/crm/contacts/${conversation.contactId}`)}
            prefetch={false}
            className="underline-offset-4 hover:underline"
          >
            {conversation.contactName || t("Visitor")}
          </Link>
        </h2>
        <dl className="flex flex-col gap-2 text-sm">
          {facts.map((fact) => (
            <div key={fact.label} className="flex flex-col">
              <dt className="text-xs text-muted-foreground">{fact.label}</dt>
              <dd className="truncate">{fact.value}</dd>
            </div>
          ))}
        </dl>
      </section>
      <ContactDeals conversationId={conversation.id} />
      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-medium">{t("Earlier conversations")}</h2>
        {history.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("This is the first conversation with this contact.")}
          </p>
        ) : (
          <ItemGroup>
            {history.map((earlier) => (
              <Item
                key={earlier.id}
                variant="outline"
                size="sm"
                render={
                  <Link
                    href={toAppHref(`/inbox/${earlier.id}`)}
                    prefetch={false}
                  />
                }
              >
                <ItemContent>
                  <ItemTitle>{earlier.subject ?? t("No subject")}</ItemTitle>
                  <ItemDescription>
                    {earlier.lastMessageAt
                      ? format.dateTime(new Date(earlier.lastMessageAt), {
                          dateStyle: "medium",
                        })
                      : t("No messages")}
                  </ItemDescription>
                </ItemContent>
                <Badge
                  variant={
                    earlier.status === "resolved"
                      ? "success-light"
                      : "info-light"
                  }
                >
                  {earlier.status === "resolved" ? t("Resolved") : t("Open")}
                </Badge>
              </Item>
            ))}
          </ItemGroup>
        )}
      </section>
    </aside>
  );
}
