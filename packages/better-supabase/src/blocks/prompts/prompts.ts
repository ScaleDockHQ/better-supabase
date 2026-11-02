import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  applyTemporal,
  blockCall,
  instantOf,
  optionalText,
  recordOf,
  textOf,
} from "../shared.ts";

/** One saved, immutable version of a named prompt template. */
export interface PromptVersion {
  readonly id: string;
  /** The tenant that owns the prompt; `undefined` for a system prompt. */
  readonly organizationId: string | undefined;
  readonly name: string;
  readonly version: number;
  readonly template: string;
  /** The variable names the template expects. */
  readonly variables: readonly string[];
  readonly createdAt: Temporal.Instant | undefined;
  /** The labels pointing at this version; set by `versions` only. */
  readonly labels: readonly string[];
}

/** A prompt resolved by label or version, ready to render. */
export interface Prompt extends PromptVersion {
  /** Fills the variables and throws when one is missing or undeclared. */
  render(values: Readonly<Record<string, string | number | boolean>>): string;
}

export interface PromptSaveOptions {
  /** The tenant that owns the prompt. Omit for a system prompt. */
  readonly organizationId?: string;
  /** Variable names; default: the `{{name}}` placeholders in the template. */
  readonly variables?: readonly string[];
  /** A label (such as `production`) to move to the new version. */
  readonly label?: string;
}

export interface PromptOptions extends BlockTemporalOptions {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Prompts>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  /** Calls as the service role: templates can hold instructions and secrets. */
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface Prompts {
  /**
   * Creates the next version from `template` as the next version of `name`.
   * Versions never change.
   */
  create(
    input: { name: string; template: string } & PromptSaveOptions,
  ): AsyncResult<PromptVersion>;
  /**
   * The version `label` (default `production`) points at, or an exact
   * `version`. A tenant's prompt wins over the system prompt of that name.
   * `undefined` when there is none.
   */
  get(
    input: { name: string } & {
      readonly label?: string;
      readonly version?: number;
      readonly organizationId?: string;
    },
  ): AsyncResult<Prompt | undefined>;
  /** Points `label` at an existing version, to promote or roll back. */
  setLabel(
    input: { name: string; label: string; version: number } & {
      readonly organizationId?: string;
    },
  ): AsyncResult<PromptVersion>;
  /** Every version of `name`, newest first, with its labels. */
  versions(
    input: { name: string } & { readonly organizationId?: string },
  ): AsyncResult<readonly PromptVersion[]>;
}

const PLACEHOLDER = /\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}/g;

function placeholders(template: string): string[] {
  return [
    ...new Set(
      [...template.matchAll(PLACEHOLDER)].flatMap((match) =>
        match[1] === undefined ? [] : [match[1]],
      ),
    ),
  ];
}

/**
 * Fills the `{{name}}` placeholders of `template`. A value is inserted as text,
 * never evaluated. It throws on a placeholder without a value or a value the
 * template doesn't use, so a renamed variable fails loudly.
 */
export function renderPrompt(
  template: string,
  values: Readonly<Record<string, string | number | boolean>>,
): string {
  const used = new Set(placeholders(template));

  for (const name of used) {
    if (!Object.hasOwn(values, name)) {
      throw new TypeError(`Prompt variable "${name}" has no value`);
    }
  }

  for (const name of Object.keys(values)) {
    if (!used.has(name)) {
      throw new TypeError(`Prompt has no variable "${name}"`);
    }
  }

  return template.replaceAll(PLACEHOLDER, (_match, name: string) =>
    String(values[name]),
  );
}

function versionOf(value: unknown): PromptVersion {
  const row = recordOf(value, "prompt_versions");
  const variables = row["variables"];
  const labels = row["labels"];

  const names = (list: unknown): string[] =>
    Array.isArray(list)
      ? list.filter((item): item is string => typeof item === "string")
      : [];

  return {
    id: textOf(row["id"]),
    organizationId: optionalText(row["organization_id"]),
    name: textOf(row["name"]),
    version: Number(row["version"]),
    template: textOf(row["template"]),
    variables: names(variables),
    createdAt:
      row["created_at"] === null || row["created_at"] === undefined
        ? undefined
        : instantOf(row["created_at"]),
    labels: names(labels),
  };
}

/**
 * Versioned prompt templates in Postgres with labels, read and written as the
 * service role.
 */
export function createPrompts(options: PromptOptions): Prompts {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const client: Prompts = {
    create: ({ name, template, ...saveOptions }) =>
      call(
        "create_prompt_version",
        {
          name,
          template,
          tenant: saveOptions.organizationId,
          variables: saveOptions.variables ?? placeholders(template),
          label: saveOptions.label,
        },
        versionOf,
      ),
    get: ({ name, ...getOptions }) =>
      call(
        "get_prompt",
        {
          name,
          label: getOptions.label ?? "production",
          version: getOptions.version,
          tenant: getOptions.organizationId,
        },
        (value) => {
          if (value === null || value === undefined) {
            return;
          }

          const found = versionOf(value);

          return {
            ...found,
            render: (values) => renderPrompt(found.template, values),
          };
        },
      ),
    setLabel: ({ name, label, version, ...labelOptions }) =>
      call(
        "set_prompt_label",
        { name, label, version, tenant: labelOptions.organizationId },
        versionOf,
      ),
    versions: ({ name, ...listOptions }) =>
      call(
        "list_prompt_versions",
        { name, tenant: listOptions.organizationId },
        (value) => (Array.isArray(value) ? value.map(versionOf) : []),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "prompts",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
