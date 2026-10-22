import { readFileSync } from "node:fs";

import type { Snapshot } from "../../../src/cli/introspect/types.ts";

/**
 * A file in better-supabase's test fixtures. The CLI renders the generated
 * fixtures there from the same snapshot the library tests read.
 */
export const libraryFixture = (name: string): URL =>
  new URL(`../../fixtures/${name}`, import.meta.url);

export const readJsonFixture = (name: string): unknown =>
  JSON.parse(readFileSync(libraryFixture(name), "utf-8"));

/** The fixture database's snapshot, which CI checks against a fresh stack. */
export const snapshotPath: URL = new URL(
  "../../../../../supabase/snapshot.json",
  import.meta.url,
);

// SAFETY: supabase/snapshot.json is written by `better-supabase gen --save-snapshot`.
export const snapshotFixture = JSON.parse(
  readFileSync(snapshotPath, "utf-8"),
) as Snapshot;

/**
 * A snapshot with the SQL module tables in `better_supabase` (memberships,
 * invitations), for doctor rules the fixture database has no tables for.
 */
// SAFETY: module-snapshot.json is written by `better-supabase gen --save-snapshot`.
export const moduleSnapshotFixture = JSON.parse(
  readFileSync(new URL("module-snapshot.json", import.meta.url), "utf-8"),
) as Snapshot;
