// #region recipe:presence-avatars
"use client";

import { usePresence } from "better-supabase/react";
import {
  subjectPresenceTopic,
  subjectPresenceValues,
} from "better-supabase/realtime";
import { useExtracted } from "next-intl";
import * as v from "valibot";

import {
  Avatar,
  AvatarFallback,
  AvatarGroup,
  AvatarGroupCount,
} from "@/components/ui/avatar";
import { useSession } from "@/lib/hooks";

const SHOWN = 4;

/** States that fail the schema never reach `members`. */
const viewers = subjectPresenceTopic(
  v.object({ userId: v.string(), name: v.string() }),
);

/**
 * Who else has a record open: a channel, a comment thread's record or a
 * document. The subjects module lets anyone who reads the record join its
 * presence topic. States come from the clients, so they only label avatars.
 */
export function PresenceAvatars({
  subject,
}: {
  subject: { readonly type: string; readonly id: string };
}) {
  const t = useExtracted("chat");
  const session = useSession();
  const me = session.kind === "user" ? session.user : null;

  const { members } = usePresence(
    viewers,
    subjectPresenceValues(me ? subject : null),
    { state: me ? { userId: me.id, name: me.email ?? t("Someone") } : null },
  );

  const others = new Map<string, string>();

  for (const { state } of members) {
    if (state.userId !== me?.id) {
      others.set(state.userId, state.name);
    }
  }

  if (others.size === 0) {
    return null;
  }

  const people = [...others];

  return (
    <AvatarGroup
      aria-label={t(
        "{count, plural, one {# other viewer} other {# other viewers}}",
        { count: people.length },
      )}
    >
      {people.slice(0, SHOWN).map(([userId, name]) => (
        <Avatar key={userId} size="sm" title={name}>
          <AvatarFallback>{name.charAt(0).toUpperCase()}</AvatarFallback>
        </Avatar>
      ))}
      {people.length > SHOWN ? (
        <AvatarGroupCount>+{people.length - SHOWN}</AvatarGroupCount>
      ) : null}
    </AvatarGroup>
  );
}
// #endregion recipe:presence-avatars
