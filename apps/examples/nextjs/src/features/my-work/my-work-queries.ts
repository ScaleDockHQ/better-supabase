import "server-only";
import type { MyWorkKind } from "better-supabase/blocks/subjects";

import { tenantOf } from "better-supabase/next";
import { loadMyWork } from "better-supabase/records";
import { unstable_rethrow } from "next/navigation";

import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

export interface MyWorkRow {
  readonly key: string;
  readonly kind: MyWorkKind;
  readonly title: string;
  readonly url: string | null;
  /** Epoch milliseconds: the due date, or when it arrived. */
  readonly at: number | null;
}

export interface MyWorkView {
  readonly rows: readonly MyWorkRow[];
  readonly counts: Readonly<Record<MyWorkKind, number>>;
}

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "no-organization" }
  | { readonly kind: "error" };

/**
 * What waits on the caller in the organization: assigned work, approvals, due
 * reminders, mentions and SLA warnings. Throws on a failed read, so the private
 * cache never keeps an error.
 */
async function loadView(): Promise<MyWorkView | null> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const work = await loadMyWork(blocks(supabase, tenant).subjects, {
    tenant,
  }).orThrow();

  return {
    rows: work.items.map((item) => ({
      key: `${item.kind}:${item.ref}`,
      kind: item.kind,
      title: item.title ?? item.subject.id,
      url: item.url ?? null,
      at: item.at?.epochMilliseconds ?? null,
    })),
    counts: work.counts,
  };
}

export async function getMyWork(): Promise<Loaded<MyWorkView>> {
  try {
    const data = await loadView();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
