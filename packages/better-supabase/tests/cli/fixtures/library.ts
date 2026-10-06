import { readFileSync } from "node:fs";

import type { Snapshot } from "../../../src/cli/introspect/types.ts";

/**
 * A file in better-supabase's test fixtures. The CLI renders the generated
 * fixtures there from the same snapshot the library tests read.
 */
export const libraryFixture = (name: string): URL =>
  new URL(`../../fixtures/${name}`, import.meta.url);

export const readJsonFixture = (name: string): unknown =>
  JSON.parse(readFileSync(libraryFixture(name), "utf8"));

// SAFETY: snapshot.json is written by `better-supabase introspect`.
export const snapshotFixture = readJsonFixture("snapshot.json") as Snapshot;

/**
 * A snapshot with the SQL module tables in `better_supabase` (memberships,
 * invitations), for doctor rules the fixture database has no tables for.
 */
// SAFETY: module-snapshot.json is written by `better-supabase introspect`.
export const moduleSnapshotFixture = JSON.parse(
  readFileSync(new URL("module-snapshot.json", import.meta.url), "utf8"),
) as Snapshot;
