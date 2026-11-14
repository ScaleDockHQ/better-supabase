import "server-only";
import type {
  SequenceCounts,
  SequenceStatus,
  SequenceStep,
} from "better-supabase/blocks/sequences";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

import { SEQUENCES_TAG } from "./sequences-cache";

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
  cacheTag(SEQUENCES_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const sequences = await db.sequences.list({ limit: 100 }).orThrow();

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

/** One sequence, `undefined` when it is gone or hidden. */
export async function getSequence(
  id: string,
): Promise<Loaded<SequenceCard | undefined>> {
  const sequences = await getSequences();

  return sequences.kind === "ok"
    ? {
        kind: "ok",
        data: sequences.data.find((sequence) => sequence.id === id),
      }
    : sequences;
}
