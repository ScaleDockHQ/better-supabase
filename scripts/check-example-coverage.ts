// Fails when a catalog block or preset has no entry in the Next.js example's
// coverage map, when a listed route has no `page.tsx`, or when the map names
// a block or preset the catalog does not have. Prints how many blocks still
// wait for their screen. Run with `node scripts/check-example-coverage.ts`.
import { existsSync } from "node:fs";
import { join } from "node:path";
import { argv, exit } from "node:process";

import type { CoverageEntry } from "../apps/examples/nextjs/coverage/block-coverage.ts";

import {
  BLOCK_COVERAGE,
  PRESET_TOURS,
} from "../apps/examples/nextjs/coverage/block-coverage.ts";
import { PRESET_CATALOG } from "../packages/better-supabase/src/preset/catalog.generated.ts";
import { PRESET_NAMES } from "../packages/better-supabase/src/preset/presets.ts";

const APP = "apps/examples/nextjs/src/app/[locale]";
const GROUPS = ["(app)", "(auth)", "(public)"] as const;

export const routeExists = (route: string, root = APP): boolean => {
  const path = route === "/" ? "" : route;

  return GROUPS.some((group) =>
    existsSync(join(root, group, path, "page.tsx")),
  );
};

const routesOf = (entry: CoverageEntry): readonly string[] =>
  "routes" in entry ? (entry.routes ?? []) : [];

export interface CoverageReport {
  readonly problems: readonly string[];
  readonly planned: number;
  readonly covered: number;
  readonly noUi: number;
}

export const checkCoverage = (
  blocks: readonly string[] = PRESET_CATALOG.blocks.map((block) => block.name),
  presets: readonly string[] = PRESET_NAMES,
  root = APP,
): CoverageReport => {
  const problems: string[] = [];
  let planned = 0;
  let covered = 0;
  let noUi = 0;

  for (const name of blocks) {
    const entry = BLOCK_COVERAGE[name];

    if (!entry) {
      problems.push(`Block "${name}" has no entry in block-coverage.ts`);
      continue;
    }

    if ("noUi" in entry) {
      noUi += 1;

      if (entry.noUi.trim() === "") {
        problems.push(`Block "${name}" has an empty noUi reason`);
      }
    } else if ("planned" in entry) {
      planned += 1;
    } else {
      covered += 1;

      if (entry.routes.length === 0) {
        problems.push(`Block "${name}" lists no routes`);
      }
    }

    for (const route of routesOf(entry)) {
      if (!routeExists(route, root)) {
        problems.push(`Block "${name}" lists ${route}, which has no page.tsx`);
      }
    }
  }

  for (const name of Object.keys(BLOCK_COVERAGE)) {
    if (!blocks.includes(name)) {
      problems.push(
        `block-coverage.ts names "${name}", which is not a catalog block`,
      );
    }
  }

  for (const name of presets) {
    const tour = PRESET_TOURS[name];

    if (!tour || tour.length === 0) {
      problems.push(`Preset "${name}" has no tour in block-coverage.ts`);
      continue;
    }

    for (const route of tour) {
      if (!routeExists(route, root)) {
        problems.push(`Preset "${name}" tours ${route}, which has no page.tsx`);
      }
    }
  }

  for (const name of Object.keys(PRESET_TOURS)) {
    if (!presets.includes(name)) {
      problems.push(`block-coverage.ts tours "${name}", which is not a preset`);
    }
  }

  return { problems, planned, covered, noUi };
};

if (argv[1] === import.meta.filename) {
  const report = checkCoverage();

  console.log(
    `Example coverage: ${report.covered} blocks on a screen, ${report.noUi} without UI, ${report.planned} planned.`,
  );

  if (report.problems.length > 0) {
    for (const problem of report.problems) {
      console.error(problem);
    }

    exit(1);
  }
}
