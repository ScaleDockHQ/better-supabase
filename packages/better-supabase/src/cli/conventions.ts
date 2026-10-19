import type {
  ConfigConventions,
  Preset,
  PresetFieldKey,
} from "../preset/index.ts";
import type { Prompter } from "./prompts.ts";

import {
  DEFAULT_CONVENTIONS,
  presetField,
  presetValueLabel,
  PRESET_TENANT_NAMES,
  withPresetField,
} from "../preset/index.ts";
import { CliError } from "./core/errors.ts";

type ConventionKey = keyof ConfigConventions;

/** One convention flag. */
export interface ConventionArg {
  readonly type: "string";
  readonly description: string;
  readonly valueHint: string;
}

const arg = (key: PresetFieldKey, description: string): ConventionArg => ({
  type: "string",
  description,
  valueHint: presetField(key).values.join("|"),
});

/** The convention flags `init` and `apply` take; each one overrides the preset. */
export const CONVENTION_ARGS: {
  readonly casing: ConventionArg;
  readonly scope: ConventionArg;
  readonly "tenant-name": ConventionArg;
  readonly access: ConventionArg;
  readonly "id-type": ConventionArg;
  readonly api: ConventionArg;
} = {
  casing: arg(
    "casing",
    "Row keys: snake keeps the database's names (the default), camel renames them in the query",
  ),
  scope: arg(
    "scope",
    "Row ownership (sql.scope): tenant (the default), user or none for one shared space",
  ),
  "tenant-name": {
    type: "string",
    description:
      "What a tenant is called (sql.naming.tenant): organization (the default), workspace, team or another lowercase name",
    valueHint: "name",
  },
  access: arg(
    "access",
    "Auth and permissions (blocks.access.model): roles (the default), catalog, provider or custom",
  ),
  "id-type": arg(
    "idType",
    "The type of the access block's ids (blocks.access.idType): uuid (the default), text, bigint or integer",
  ),
  api: arg(
    "api",
    "API schema (sql.api): none (the default) or api for security invoker wrappers in an api schema",
  ),
};

/** The flag of each convention. */
const FLAGS: { readonly [K in ConventionKey]: keyof typeof CONVENTION_ARGS } = {
  casing: "casing",
  scope: "scope",
  tenantName: "tenant-name",
  access: "access",
  idType: "id-type",
  api: "api",
};

/** Every convention, in the order `init` asks for them (as on /create). */
const KEYS: readonly ConventionKey[] = [
  "casing",
  "scope",
  "tenantName",
  "access",
  "idType",
  "api",
];

const TENANT_NAME = /^[a-z][a-z0-9_]{0,40}$/;

/** The convention flags that were passed, each checked against its values. */
export function conventionFlags(args: {
  readonly [K in keyof typeof CONVENTION_ARGS]?: string | undefined;
}): Partial<ConfigConventions> {
  const out: Partial<Record<ConventionKey, string>> = {};

  for (const key of KEYS) {
    const flag = FLAGS[key];
    const value = args[flag];

    if (value === undefined) {
      continue;
    }

    if (key === "tenantName") {
      if (!TENANT_NAME.test(value)) {
        throw new CliError(
          "usage",
          `--${flag} must be a lowercase name that starts with a letter (letters, digits and _), like workspace.`,
        );
      }
    } else if (!presetField(key).values.some((each) => each === value)) {
      throw new CliError(
        "invalid_value",
        `--${flag} must be one of ${presetField(key).values.join(", ")}.`,
      );
    }

    out[key] = value;
  }

  // SAFETY: each value was checked against its field's values above.
  return out as Partial<ConfigConventions>;
}

/** Whether any convention flag was passed. */
export const hasConventionFlags = (
  flags: Partial<ConfigConventions>,
): boolean => Object.keys(flags).length > 0;

/**
 * `preset` with the flags' conventions. A preset code stores the tenant
 * names /create offers, so another `--tenant-name` throws.
 */
export function withConventions(
  preset: Preset,
  flags: Partial<ConfigConventions>,
): Preset {
  let next = preset;

  for (const key of KEYS) {
    const value = flags[key];

    if (value === undefined) {
      continue;
    }

    if (
      key === "tenantName" &&
      !PRESET_TENANT_NAMES.some((name) => name === value)
    ) {
      throw new CliError(
        "usage",
        `--tenant-name with a preset takes ${PRESET_TENANT_NAMES.join(", ")}. Leave it out and set sql.naming.tenant in the config for another name.`,
      );
    }

    next = withPresetField(next, key, value);
  }

  return next;
}

/** The conventions with the flags over the defaults, for `--yes` and CI. */
export const defaultConventions = (
  flags: Partial<ConfigConventions>,
): ConfigConventions => ({ ...DEFAULT_CONVENTIONS, ...flags });

/**
 * Asks for each convention in /create's order, with its labels and hints.
 * The tenant name is asked only for tenant scope. Undefined when the person
 * cancels.
 */
export async function promptConventions(
  prompts: Prompter,
): Promise<ConfigConventions | undefined> {
  const defaults = DEFAULT_CONVENTIONS;
  const answers: Partial<Record<keyof typeof CONVENTION_ARGS, string>> = {};

  for (const key of KEYS) {
    const scope = answers.scope ?? defaults.scope;

    if (key === "tenantName" && scope !== "tenant") {
      continue;
    }

    const field = presetField(key);

    const values: readonly string[] =
      key === "tenantName" ? PRESET_TENANT_NAMES : field.values;

    const picked = await prompts.select(
      field.label,
      values.map((value) => {
        const info = presetValueLabel(key, value);

        return {
          value,
          label: info.label,
          ...(info.hint === undefined ? {} : { hint: info.hint }),
        };
      }),
      defaults[key],
    );

    if (picked === undefined) {
      return undefined;
    }

    answers[FLAGS[key]] = picked;
  }

  return { ...defaults, ...conventionFlags(answers) };
}

/** The values a shell offers for each convention flag. */
export const CONVENTION_COMPLETIONS: {
  readonly [K in keyof typeof CONVENTION_ARGS]: () => readonly string[];
} = {
  casing: () => presetField("casing").values,
  scope: () => presetField("scope").values,
  "tenant-name": () => PRESET_TENANT_NAMES,
  access: () => presetField("access").values,
  "id-type": () => presetField("idType").values,
  api: () => presetField("api").values,
};
