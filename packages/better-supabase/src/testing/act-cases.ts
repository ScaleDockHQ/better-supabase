import type { SessionActor } from "../auth/actor.ts";

import cases from "../../testing/act-cases.json" with { type: "json" };

/** One `act` claim set, with what `actorOf` and `actor_may_write()` say about it. */
export interface ActCase {
  readonly name: string;
  /** Only the claims the verdict reads: `act`, `client_id` and `scope`. */
  readonly claims: Readonly<Record<string, unknown>>;
  /** `false` when the chain is invalid and the session must be refused. */
  readonly valid: boolean;
  /** The actor's kind; `null` without an actor or for an invalid chain. */
  readonly kind: SessionActor["kind"] | null;
  /** The actor's `readOnly` (support and agent); `null` otherwise. */
  readonly readOnly: boolean | null;
  /** An agent's `tools`; `null` when it lists none, which means every tool. */
  readonly tools: readonly string[] | null;
  /** What `better_supabase.actor_may_write()` returns for these claims. */
  readonly mayWrite: boolean;
}

/** `better-supabase/testing/act-cases.json`, versioned so other parsers can pin it. */
export interface ActCases {
  readonly version: 1;
  readonly cases: readonly ActCase[];
}

/**
 * The RFC 8693 `act` chains better-supabase accepts and refuses, as plain
 * JSON (`better-supabase/testing/act-cases.json`), so another library that
 * reads the same claims can run the same cases.
 */
// SAFETY: the JSON import widens `version` and `kind` to number and string; tests/testing/act-cases.test.ts checks every case against actorOf.
export const actCases: ActCases = cases as ActCases;
