"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

import type { DbError } from "../../../core/errors.ts";
import type { Result } from "../../../core/result.ts";
import type { SubscriptionStatus } from "../../../realtime/index.ts";
import type { Announcement } from "../announcements.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useAuth, useSupabase } from "../../../react/hooks.ts";
import { watchTopic } from "../../react-topic.ts";
import { createAnnouncements } from "../announcements.ts";

export interface UseAnnouncementsOptions {
  /** The active tenant, for tenant, role and plan audiences. */
  readonly organizationId?: string | null;
  /** The topic the module broadcasts to (`sql.modules.announcements.options.topic`); `null` loads once. */
  readonly topic?: string | null;
  /** The module schema, default `better_supabase`. */
  readonly schema?: string;
}

export interface AnnouncementsState {
  /** `undefined` until the first load. */
  readonly items: readonly Announcement[] | undefined;
  readonly status: SubscriptionStatus;
  readonly error: DbError | undefined;
  /** Hides one for the user, then drops it from `items`. */
  readonly dismiss: (announcementId: string) => Promise<void>;
  readonly refresh: () => Promise<void>;
}

/**
 * The signed-in user's live announcements, loaded again whenever staff
 * publish, change or remove one.
 *
 * ```tsx
 * const { items, dismiss } = useAnnouncements({ organizationId });
 * ```
 */
export function useAnnouncements(
  options: UseAnnouncementsOptions = {},
): AnnouncementsState {
  const supabase = useSupabase();
  const auth = useAuth();
  const [items, setItems] = useState<readonly Announcement[] | undefined>(
    undefined,
  );
  const [error, setError] = useState<DbError | undefined>(undefined);
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  const organizationId = options.organizationId ?? null;
  const topic = options.topic === undefined ? "announcements" : options.topic;
  const schema = options.schema;
  const client = useMemo(
    () =>
      createAnnouncements({
        transport: rpcTransport(supabase),
        ...(schema === undefined ? {} : { schema }),
      }),
    [supabase, schema],
  );
  const userId = auth.user?.id ?? null;
  const signedIn = auth.status === "signed-in";

  const apply = useCallback((result: Result<readonly Announcement[]>) => {
    if (result.ok) {
      setItems(result.data);
      setError(undefined);
    } else {
      setError(result.error);
    }
  }, []);

  const refresh = useCallback(async () => {
    apply(await client.listActive(organizationId));
  }, [client, organizationId, apply]);

  const dismiss = useCallback(
    async (announcementId: string) => {
      const result = await client.dismiss(announcementId);
      if (!result.ok) {
        setError(result.error);
        return;
      }
      setItems((current) =>
        current?.filter((item) => item.id !== announcementId),
      );
    },
    [client],
  );

  useEffect(() => {
    if (!signedIn) return;
    let active = true;
    const load = () =>
      void client.listActive(organizationId).then((result) => {
        if (active) apply(result);
      });
    load();
    const leave = topic
      ? watchTopic(supabase, topic, {
          onMessage: load,
          onRejoin: load,
          onStatus: setStatus,
        })
      : undefined;
    return () => {
      active = false;
      leave?.();
    };
    // oxlint-disable-next-line react/exhaustive-effect-dependencies -- userId reloads and resubscribes for the new user.
  }, [client, supabase, topic, organizationId, signedIn, userId, apply]);

  return { items, status, error, dismiss, refresh };
}
