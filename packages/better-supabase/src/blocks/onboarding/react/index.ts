"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

import type { DbError } from "../../../core/errors.ts";
import type { Result } from "../../../core/result.ts";
import type {
  Checklist,
  ChecklistProgress,
  ChecklistScope,
  ChecklistSubject,
} from "../onboarding.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useAuth, useSupabase } from "../../../react/hooks.ts";

export interface UseOnboardingOptions {
  /** The organization, for an organization checklist. */
  readonly organizationId?: string | null;
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `sql.modules.<module>.api`. */
  readonly schema?: string;
}

export interface OnboardingState<Id extends string> {
  /** `undefined` until the first load. */
  readonly progress: ChecklistProgress<Id> | undefined;
  readonly error: DbError | undefined;
  /** Marks a step done, then loads the progress again. */
  readonly complete: (step: Id) => Promise<void>;
  readonly reset: (step: Id) => Promise<void>;
  readonly refresh: () => Promise<void>;
}

/**
 * A checklist's progress for the signed-in user, or for an organization
 * with `organizationId`, through the browser client.
 *
 * ```tsx
 * const { progress, complete } = useOnboarding(gettingStarted, { organizationId });
 * ```
 */
export function useOnboarding<Id extends string, Scope extends ChecklistScope>(
  checklist: Checklist<Id, Scope>,
  options: UseOnboardingOptions = {},
): OnboardingState<Id> {
  const supabase = useSupabase();
  const auth = useAuth();
  const [progress, setProgress] = useState<ChecklistProgress<Id> | undefined>(
    undefined,
  );
  const [error, setError] = useState<DbError | undefined>(undefined);
  const organizationId = options.organizationId ?? null;
  const schema = options.schema;
  const ready =
    auth.status === "signed-in" &&
    (checklist.scope === "user" || organizationId !== null);
  const bound = useMemo(() => {
    const client = checklist.connect({
      transport: rpcTransport(supabase),
      ...(schema === undefined ? {} : { schema }),
    });
    // SAFETY: ChecklistSubject is [organizationId] for organization checklists and [] for user ones.
    const subject = (
      checklist.scope === "organization" && organizationId !== null
        ? [organizationId]
        : []
    ) as ChecklistSubject<Scope>;
    return {
      progress: () => client.progress(...subject),
      complete: (step: Id) => client.complete(step, ...subject),
      reset: (step: Id) => client.reset(step, ...subject),
    };
  }, [checklist, supabase, schema, organizationId]);
  const userId = auth.user?.id ?? null;

  const apply = useCallback((result: Result<ChecklistProgress<Id>>) => {
    if (result.ok) {
      setProgress(result.data);
      setError(undefined);
    } else {
      setError(result.error);
    }
  }, []);

  const refresh = useCallback(async () => {
    apply(await bound.progress());
  }, [bound, apply]);

  const change = useCallback(
    async (action: "complete" | "reset", step: Id) => {
      const result = await bound[action](step);
      if (result.ok) await refresh();
      else setError(result.error);
    },
    [bound, refresh],
  );

  useEffect(() => {
    if (!ready) return;
    let active = true;
    void bound.progress().then((result) => {
      if (active) apply(result);
    });
    return () => {
      active = false;
    };
    // oxlint-disable-next-line react/exhaustive-effect-dependencies -- userId reloads for the new user.
  }, [bound, apply, ready, userId]);

  return {
    progress,
    error,
    complete: (step) => change("complete", step),
    reset: (step) => change("reset", step),
    refresh,
  };
}
