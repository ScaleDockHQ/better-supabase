import { MessagesSquareIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import type { RecordSubject } from "../record-subject";

import { getRecordConversations } from "../records-queries";

/**
 * Render inside `<Suspense>`: the inbox threads of the people linked to a
 * record, each linking to the inbox. Renders nothing without `inbox.read`.
 */
// skeleton: RecordSectionSkeleton in the record detail kit, rendered by the caller
export async function RecordConversations({
  subject,
}: {
  subject: RecordSubject;
}) {
  const [t, permissions] = await Promise.all([
    getExtracted("records"),
    getPermissions(),
  ]);

  if (!can(permissions, "inbox.read")) {
    return null;
  }

  const conversations = await getRecordConversations(subject);

  return (
    <Card size="sm" id="conversations">
      <CardHeader>
        <CardTitle>{t("Conversations")}</CardTitle>
        <CardDescription>
          {t("Threads of the people linked to this record.")}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-2">
        {conversations.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("No conversation yet.")}
          </p>
        ) : (
          conversations.map((conversation) => (
            <Link
              key={conversation.id}
              href={`/inbox/${conversation.id}`}
              className="flex items-center gap-2 text-sm hover:underline"
            >
              <MessagesSquareIcon aria-hidden className="size-4" />
              <span className="min-w-0 flex-1 truncate">
                {conversation.subject ?? conversation.contactName}
              </span>
              <Badge variant="secondary">{conversation.status}</Badge>
            </Link>
          ))
        )}
      </CardContent>
    </Card>
  );
}
