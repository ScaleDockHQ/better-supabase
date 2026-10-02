import { readFileSync } from "node:fs";

import type { Snapshot } from "../../src/introspect/types.ts";

/**
 * A file in better-supabase's test fixtures. The CLI renders the generated
 * fixtures there from the same snapshot the library tests read.
 */
export const libraryFixture = (name: string): URL =>
  new URL(`../../../better-supabase/tests/fixtures/${name}`, import.meta.url);

export const readJsonFixture = (name: string): unknown =>
  JSON.parse(readFileSync(libraryFixture(name), "utf8"));

// SAFETY: snapshot.json is written by `better-supabase introspect`.
export const snapshotFixture = readJsonFixture("snapshot.json") as Snapshot;
