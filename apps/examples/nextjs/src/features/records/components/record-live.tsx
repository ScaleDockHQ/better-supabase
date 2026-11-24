"use client";

import { useBlockEnv, useBlockTenant } from "better-supabase/react";
import { useEffect, useRef } from "react";

import { useRouter } from "@/i18n/navigation";

/** At most one refetch in this window, however many signals arrive. */
const THROTTLE_MS = 3000;

/**
 * Refetches the page's server data when one of the organization's realtime
 * topics signals a change. The signal carries no data: the page reads again
 * under the caller's own access, and bursts collapse into one refresh.
 */
export function RecordLive({ topics }: { topics: readonly string[] }) {
  const router = useRouter();
  const env = useBlockEnv();
  const tenant = useBlockTenant(env);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const key = topics.join("\n");

  useEffect(() => {
    if (tenant === undefined) {
      return;
    }

    const refresh = () => {
      if (timer.current !== null) {
        return;
      }

      timer.current = setTimeout(() => {
        timer.current = null;
        router.refresh();
      }, THROTTLE_MS);
    };

    const handles = key
      .split("\n")
      .map((topic) =>
        env.ports.topic(`${topic}:${tenant}`, {
          onMessage: refresh,
          onRejoin: refresh,
          onStatus: () => undefined,
        }),
      );

    return () => {
      for (const handle of handles) {
        handle.leave();
      }

      if (timer.current !== null) {
        clearTimeout(timer.current);
        timer.current = null;
      }
    };
  }, [env, tenant, key, router]);

  return null;
}
