import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import {
  hasContentMapper,
  needsRunExternalCode,
  RUN_EXTERNAL_CODE,
  supportsContentMappers,
  TSCONFIG_SNIPPET,
} from "../content-mapper.ts";
import { satisfies } from "../peers.ts";

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
];
