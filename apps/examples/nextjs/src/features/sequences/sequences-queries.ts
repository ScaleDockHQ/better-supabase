import "server-only";
import type {
  SequenceCounts,
  SequenceStatus,
  SequenceStep,
} from "better-supabase/blocks/sequences";

import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

export interface SequenceCard {
  readonly id: string;
  readonly name: string;
  readonly status: SequenceStatus;
  readonly steps: readonly SequenceStep[];
  readonly counts: SequenceCounts;
}

/** A failed read throws, so it is never cached and Retry reads again. */
async function loadSequences(): Promise<readonly SequenceCard[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const sequences = await db.sequences.list().orThrow();

  return sequences.map((sequence) => ({
    id: sequence.id,
    name: sequence.name,
    status: sequence.status,
    steps: sequence.steps,
    counts: sequence.counts,
  }));
}

export async function getSequences(): Promise<Loaded<readonly SequenceCard[]>> {
  try {
    const sequences = await loadSequences();

    return sequences === null
      ? { kind: "no-organization" }
      : { kind: "ok", data: sequences };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
