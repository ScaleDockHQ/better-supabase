import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import {
  blockSqlVersion,
  moduleFileVersion,
  SQL_MODULES,
} from "../../sql/index.ts";
import {
  hasContentMapper,
  needsRunExternalCode,
  RUN_EXTERNAL_CODE,
  supportsContentMappers,
  TSCONFIG_SNIPPET,
} from "../content-mapper.ts";
import { satisfies } from "../peers.ts";
import { VERSION } from "../version.ts";
import { moduleFiles } from "./module-files.ts";

/** `node_modules` holds a better-supabase the lockfile doesn't name. */
function installOffLock(context: DoctorContext): FindingInput[] {
  const { installed, lock } = context.install ?? {};

  if (
    installed === undefined ||
    lock === undefined ||
    lock.versions.length === 0 ||
    lock.versions.includes(installed)
  ) {
    return [];
  }

  return [
    {
      message: `node_modules has better-supabase@${installed}, but ${lock.path} locks ${lock.versions.join(", ")}. gen, add and upgrade then write the SQL and types of a release your teammates and CI don't run. Run \`${lock.install}\`.`,
      target: lock.path,
    },
  ];
}

const AHEAD =
  "A newer better-supabase release wrote it, so this install is behind: install the release your lockfile and teammates use, then run `better-supabase upgrade --check`.";

/** Block files or `better_supabase.blocks` rows newer than this release. */
async function blocksAhead(context: DoctorContext): Promise<FindingInput[]> {
  if (context.config.blockNames.length === 0) {
    return [];
  }

  const ships = `better-supabase@${VERSION}`;
  const findings: FindingInput[] = [];

  for (const { file, path, installed } of await moduleFiles(context)) {
    const version = moduleFileVersion(file.contents)?.version ?? 1;

    if (
      file.kind !== "schema" ||
      installed === undefined ||
      installed <= version
    ) {
      continue;
    }

    findings.push({
      message: `${path} has ${file.instance ?? file.module} version ${String(installed)}; ${ships} ships version ${String(version)}. ${AHEAD}`,
      target: path,
      location: { file: path, line: 1 },
    });
  }

  const db = context.database;

  if (!db || "skipped" in db) {
    return findings;
  }

  let rows: { name: string; block: string | null; version: number }[];

  try {
    rows = await db.query(
      "select name, to_jsonb(b) ->> 'block' as block, version from better_supabase.blocks b",
    );
  } catch {
    return findings;
  }

  for (const row of rows) {
    const instance = context.config.instances[row.name];
    const module = SQL_MODULES[row.block ?? instance?.block ?? row.name];

    if (!module || instance === undefined) {
      continue;
    }

    const version = blockSqlVersion(module);

    if (row.version <= version) {
      continue;
    }

    findings.push({
      message: `The database has ${row.name} version ${String(row.version)}; ${ships} ships version ${String(version)}. ${AHEAD}`,
      target: `better_supabase.blocks.${row.name}`,
    });
  }

  return findings;
}

async function releaseMismatch(
  context: DoctorContext,
): Promise<FindingInput[]> {
  return [...installOffLock(context), ...(await blocksAhead(context))];
}

function contentMapperSetup(context: DoctorContext): FindingInput[] {
  const setup = context.contentMapper;

  if (context.config.gen.contentMapper !== true || setup === undefined) {
    return [];
  }

  const findings: FindingInput[] = [];

  if (!hasContentMapper(setup.tsconfig)) {
    findings.push({
      message: `gen.contentMapper is on, but tsconfig.json doesn't list the content mapper, so schema.bsb has no types. Add ${TSCONFIG_SNIPPET} next to compilerOptions, or run \`better-supabase init --content-mapper\`.`,
      target: "tsconfig.json",
    });
  }

  if (
    setup.typescript === undefined ||
    !supportsContentMappers(setup.typescript)
  ) {
    findings.push({
      message: `gen.contentMapper needs TypeScript 7.1 or later, but the project resolves ${setup.typescript === undefined ? "no typescript" : `typescript@${setup.typescript}`}. Install typescript@7.1, or turn gen.contentMapper off and run \`better-supabase gen\` to write the files again.`,
      target: "typescript",
    });
  }

  if (setup.typecheck !== undefined && needsRunExternalCode(setup.typecheck)) {
    findings.push({
      message: `The typecheck script runs tsc without ${RUN_EXTERNAL_CODE}, so tsc doesn't load the content mapper and every import of schema.bsb fails. Add ${RUN_EXTERNAL_CODE} to it.`,
      target: "package.json",
    });
  }

  return findings;
}

export const DEPENDENCY_RULES: readonly Rule[] = [
  {
    code: "BS601",
    severity: "warning",
    title: "Peer outside its range",
    description:
      "An optional peer of better-supabase is installed at a version outside the range better-supabase declares. With strict peer checks the install fails, and the subpath that needs the peer can break at runtime.",
    check: (context) =>
      (context.peers ?? []).flatMap((peer) =>
        peer.installed !== undefined &&
        satisfies(peer.installed, peer.range) === false
          ? [
              {
                message: `${peer.name}@${peer.installed} is installed, but better-supabase needs ${peer.range}. Install a version in that range, or remove ${peer.name} if nothing imports it.`,
                target: peer.name,
              },
            ]
          : [],
      ),
  },
  {
    code: "BS602",
    severity: "error",
    title: "Content mapper not set up",
    description:
      "gen.contentMapper is on, but tsc can't load the content mapper: tsconfig.json has no contentMappers entry for better-supabase, the project resolves TypeScript older than 7.1, or the typecheck script runs tsc without --runExternalCode. Imports of schema.bsb then have no types.",
    check: contentMapperSetup,
  },
  {
    code: "BS607",
    severity: "warning",
    title:
      "Installed better-supabase differs from the lockfile or the database",
    description:
      "The better-supabase in `node_modules` is not a version the lockfile resolves, or a block file or `better_supabase.blocks` records a block version newer than the installed release ships. Either way the CLI renders SQL and types for another release than the one your team and CI run. Run the package manager's install, or install the release that wrote the newer blocks.",
    check: releaseMismatch,
  },
];
