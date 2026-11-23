import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { blockFileState } from "../../sql/index.ts";
import { diffEngine, sqlWorkflow } from "../supabase-config.ts";
import { moduleFiles } from "./module-files.ts";
import { lineOf } from "./shared.ts";

const COMMENT_WITH_TAGS = /\bcomment\s+on\b[^;]*?@bsb\b/iu;
const GRANT = /^\s*grant\s/imu;
const SECURITY_INVOKER = /\bsecurity_invoker\s*=\s*(?:true|on)\b/iu;
const BSB_TAG = /@bsb\b/u;

/** Whether the project diffs its schema files with migra. */
function usesMigra(context: DoctorContext): boolean {
  const toml = context.configToml;

  return (
    toml !== undefined &&
    diffEngine(toml) === "migra" &&
    sqlWorkflow(context.config, toml) === "migra" &&
    (context.sqlFiles ?? []).some((file) =>
      file.path.startsWith(`${toml.dir}/schemas/`),
    )
  );
}

function migraDrops(context: DoctorContext): FindingInput[] {
  if (!usesMigra(context)) {
    return [];
  }

  const findings: FindingInput[] = [];
  const schemas = `${context.configToml?.dir ?? "supabase"}/schemas/`;

  for (const file of context.sqlFiles ?? []) {
    if (!file.path.startsWith(schemas)) {
      continue;
    }

    const tags = COMMENT_WITH_TAGS.exec(file.text);

    if (tags !== null) {
      findings.push({
        severity: "error",
        message: `${file.path} holds a \`comment on\` with \`@bsb\` tags, and a migra diff drops comments, so the tags (owner, policies, access) would be lost from the database. Switch to pg-delta (\`experimental.pgdelta.enabled = true\`) before the next \`db diff\`.`,
        target: file.path,
        location: { file: file.path, line: lineOf(file.text, BSB_TAG) ?? 1 },
      });
    }

    if (GRANT.test(file.text)) {
      findings.push({
        severity: "warning",
        message: `${file.path} has \`grant\` statements, and a migra diff drops grants, so a migration made from it leaves the role without them. Switch to pg-delta or grant in a migration.`,
        target: file.path,
        location: { file: file.path, line: lineOf(file.text, GRANT) ?? 1 },
      });
    }

    if (SECURITY_INVOKER.test(file.text)) {
      findings.push({
        severity: "warning",
        message: `${file.path} has a view with \`security_invoker\`, and a migra diff drops that option, so the view runs with its owner's rights. Switch to pg-delta or set it in a migration.`,
        target: file.path,
        location: {
          file: file.path,
          line: lineOf(file.text, SECURITY_INVOKER) ?? 1,
        },
      });
    }
  }

  return findings;
}

/**
 * The module files of the declarative workflows whose `@bsb-hash` line is gone.
 * `db pull --declarative` exports the database as new files and drops comments,
 * so the marker goes with them.
 */
async function markerGone(context: DoctorContext): Promise<FindingInput[]> {
  if (context.configToml === undefined) {
    return [];
  }

  const workflow = sqlWorkflow(context.config, context.configToml);

  if (workflow === "migrations") {
    return [];
  }

  const findings: FindingInput[] = [];

  for (const { file, path, current } of await moduleFiles(context)) {
    if (
      file.kind === "test" ||
      current === undefined ||
      blockFileState(current) !== "missing"
    ) {
      continue;
    }

    findings.push({
      message: `${path} has no \`@bsb-hash\` line, so \`gen sql\` can't tell a generated file from one you wrote. \`supabase db pull --declarative\` rewrites the files without comments. Run \`better-supabase gen sql\` to write the module file again with its marker.`,
      target: path,
      location: { file: path, line: 1 },
    });
  }

  return findings;
}

export const MIGRA_DROP_RULES: readonly Rule[] = [
  {
    code: "BS713",
    severity: "warning",
    title: "A migra diff drops part of the schema files",
    description:
      "The project diffs `supabase/schemas` with migra, which drops `comment on` statements, grants and the `security_invoker` option of views. A `comment on` that holds `@bsb` tags is an error, because the owner, policies or access the tags record would be lost from the database; grants and security-invoker views are warnings. Switch to pg-delta (`experimental.pgdelta.enabled = true`) to keep them. Reads every schema file.",
    check: migraDrops,
  },
  {
    code: "BS714",
    severity: "warning",
    title: "A module file lost its hash marker",
    description:
      "A better-supabase module file has no `@bsb-hash` line. `supabase db pull --declarative` exports the database into new files without comments, which removes the marker, and `gen sql` then can't tell the file from one you wrote. Run `better-supabase gen sql` after a pull to write the module files again.",
    check: markerGone,
  },
];
