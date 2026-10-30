import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import {
  currentPermissionKeys,
  isOldPermissionKey,
  RENAMES_CODEMOD,
} from "../../blocks/permissions/index.ts";
import {
  ENTITY_KEY_RENAMES,
  ENTITY_RENAMES_CODEMOD,
  HINT_RENAMES,
} from "../../index.ts";

const QUOTED_KEY = /(?<=(["'`]))[a-z][\w-]*\.(?:\*|[a-z][\w-]*)(?=\1)/g;

function lineAt(text: string, index: number): number {
  return text.slice(0, index).split("\n").length;
}

function next(key: string): string {
  return currentPermissionKeys(key)
    .map((each) => `\`${each}\``)
    .join(", ");
}

function finding(
  where: string,
  key: string,
  location?: FindingInput["location"],
): FindingInput {
  return {
    message: `${where} uses the permission key \`${key}\`, which is now ${next(key)}. Run \`better-supabase codemod ${RENAMES_CODEMOD}\`.`,
    target: `${where}:${key}`,
    ...(location === undefined ? {} : { location }),
  };
}

/**
 * Permission keys the naming contract renamed, in the config and app code
 * (BS422).
 */
function oldPermissionKeys(context: DoctorContext): FindingInput[] {
  const findings: FindingInput[] = [];
  const { blocks } = context.config;

  for (const [role, keys] of Object.entries(blocks.permissions?.roles ?? {})) {
    for (const key of keys) {
      if (isOldPermissionKey(key)) {
        findings.push(finding(`blocks.permissions.roles.${role}`, key));
      }
    }
  }

  for (const [name, module] of Object.entries(blocks)) {
    for (const [action, key] of Object.entries(module?.permissions ?? {})) {
      if (typeof key === "string" && isOldPermissionKey(key)) {
        findings.push(finding(`blocks.${name}.permissions.${action}`, key));
      }
    }
  }

  for (const file of context.sources) {
    for (const match of file.text.matchAll(QUOTED_KEY)) {
      const [key] = match;

      if (isOldPermissionKey(key)) {
        findings.push(
          finding(file.path, key, {
            file: file.path,
            line: lineAt(file.text, match.index),
          }),
        );
      }
    }
  }

  return findings;
}

const QUOTED_HINT = /(?<=(["'`]))[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+(?=\1)/g;

/**
 * Entity keys and hint codes the 0.47 renames changed, in the config and app
 * code (BS423). `ACTIVITY_FORBIDDEN` is an old and a new code, so it is left.
 */
function oldEntityKeysAndHints(context: DoctorContext): FindingInput[] {
  const findings: FindingInput[] = [];
  const fix = `Run \`better-supabase codemod ${ENTITY_RENAMES_CODEMOD}\`.`;

  for (const [name, entry] of Object.entries(context.config.blocks)) {
    const block = typeof entry?.block === "string" ? entry.block : name;
    const keys = ENTITY_KEY_RENAMES[block] ?? {};

    for (const key of Object.keys(entry?.entities ?? {})) {
      const renamed = Object.hasOwn(keys, key) ? keys[key] : undefined;

      if (renamed !== undefined) {
        findings.push({
          message: `blocks.${name}.entities uses the key \`${key}\`, which is now \`${renamed}\`. ${fix}`,
          target: `blocks.${name}.entities:${key}`,
        });
      }
    }
  }

  for (const file of context.sources) {
    for (const match of file.text.matchAll(QUOTED_HINT)) {
      const [hint] = match;

      const renamed = Object.hasOwn(HINT_RENAMES, hint)
        ? HINT_RENAMES[hint]
        : undefined;

      if (renamed !== undefined && hint !== "ACTIVITY_FORBIDDEN") {
        findings.push({
          message: `${file.path} matches the hint \`${hint}\`, which is now \`${renamed}\`. ${fix}`,
          target: `${file.path}:${hint}`,
          location: { file: file.path, line: lineAt(file.text, match.index) },
        });
      }
    }
  }

  return findings;
}

export const NAMING_RULES: readonly Rule[] = [
  {
    code: "BS422",
    severity: "warning",
    title: "Code or config uses a renamed permission key",
    description: `Permission keys use the block name as their area and the read, write, delete and manage verbs. The old keys keep working until the next minor, with a warning. \`better-supabase codemod ${RENAMES_CODEMOD}\` renames them in the app's code and SQL, and lists the keys that split into several.`,
    check: oldPermissionKeys,
  },
  {
    code: "BS423",
    severity: "warning",
    title: "Config or code uses a renamed entity key or hint code",
    description: `Keys in \`blocks.<name>.entities\` equal the entity's singular, and hint codes start with the entity's new name. The old keys keep working until the next minor, with a warning; \`hint\` never carries an old code (\`legacyHint\` does). \`better-supabase codemod ${ENTITY_RENAMES_CODEMOD}\` renames both.`,
    check: oldEntityKeysAndHints,
  },
];
