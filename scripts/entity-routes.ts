// Reads the `entityRoutes` manifest that `better-supabase gen` writes for the
// entity pages (ADR 0879). Node cannot import the generated module (its imports
// carry no extension), so the checks read the entries as text: each entry is
// plain data on fixed lines.
import { existsSync, readFileSync } from "node:fs";

export interface EntityRouteText {
  readonly entity: string;
  readonly name: string;
  readonly route: string;
  readonly messageKeys: readonly string[];
}

export const EXAMPLE_MANIFEST =
  "apps/examples/nextjs/src/lib/supabase/pages/routes.manifest.ts";

const ENTRY =
  /entity: "([^"]+)",\s*name: "([^"]+)",\s*route: "([^"]+)",[\s\S]*?messageKeys: \[([^\]]*)\]/g;

/** The entries of a generated route manifest, or none when the file is missing. */
export function readEntityRoutes(
  path: string = EXAMPLE_MANIFEST,
): readonly EntityRouteText[] {
  if (!existsSync(path)) {
    return [];
  }

  const source = readFileSync(path, "utf-8");

  return [...source.matchAll(ENTRY)].map(
    ([, entity = "", name = "", route = "", keys = ""]) => ({
      entity,
      name,
      route,
      messageKeys: [...keys.matchAll(/"([^"]+)"/g)].map(([, key = ""]) => key),
    }),
  );
}
