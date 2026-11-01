import type { PresetCatalogManifest } from "../../preset/index.ts";
import type { AnyCommand } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";

import { PRESET_CATALOG } from "../../preset/index.ts";
import { defineCliCommand } from "../core/command.ts";
import { commandMeta } from "../core/manifest.ts";

const LIST_ARGS = {
  explain: {
    type: "boolean",
    description:
      "Say for each automation which block's event starts it and what each action does",
  },
  all: {
    type: "boolean",
    description: "List the automations of every block, not only installed ones",
  },
} as const;

type PresetCatalogAutomation = NonNullable<
  PresetCatalogManifest["automations"]
>[number];

interface AutomationEntry extends PresetCatalogAutomation {
  readonly block: string;
  /** The block that records the trigger event, when one does. */
  readonly source: string | undefined;
  readonly actionInfo: readonly {
    readonly kind: string;
    readonly title: string | undefined;
    readonly description: string | undefined;
    readonly shippedBy: string | undefined;
  }[];
}

function entries(blockNames: readonly string[] | undefined): AutomationEntry[] {
  const manifests = PRESET_CATALOG.manifests;

  const actions = new Map(
    manifests.flatMap((manifest) =>
      (manifest.actions ?? []).map(
        (action) => [action.kind, { action, block: manifest.name }] as const,
      ),
    ),
  );

  return manifests.flatMap((manifest) =>
    blockNames !== undefined && !blockNames.includes(manifest.name)
      ? []
      : (manifest.automations ?? []).map((automation) => ({
          ...automation,
          block: manifest.name,
          source: manifests.find((other) =>
            other.events?.types.includes(automation.trigger),
          )?.name,
          actionInfo: automation.actions.map((kind) => {
            const found = actions.get(kind);

            return {
              kind,
              title: found?.action.title,
              description: found?.action.description,
              shippedBy: found?.block,
            };
          }),
        })),
  );
}

function line(entry: AutomationEntry, explain: boolean): string[] {
  const head = `${entry.block}/${entry.key}  ${entry.trigger} -> ${entry.actions.join(", ")}  (${entry.enabled ? "on" : "off"} by default)`;

  if (!explain) {
    return [head];
  }

  return [
    head,
    `  When: ${entry.source === undefined ? "an app event" : `the ${entry.source} block records`} ${entry.trigger} for a ${entry.subjectType}.`,
    ...entry.actionInfo.map(
      (action) =>
        `  Then: ${action.kind}${action.title === undefined ? " (no block ships this action; register it yourself)" : `, ${action.title}${action.description === undefined ? "" : `: ${action.description}`}${action.shippedBy === undefined ? "" : ` (from ${action.shippedBy})`}`}`,
    ),
    ...(entry.requires.length === 0
      ? []
      : [`  Needs: ${entry.requires.join(", ")}`]),
  ];
}

/** The automations the blocks ship, for `automations list`. */
export function listAutomations(
  blockNames: readonly string[] | undefined,
  explain: boolean,
): CommandResult {
  const found = entries(blockNames);

  return {
    code: 0,
    output:
      found.length === 0
        ? "No installed block ships an automation. Run `better-supabase automations list --all` to see every block's."
        : found.flatMap((entry) => line(entry, explain)).join("\n"),
    data: { automations: found },
  };
}

export const automationsListCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("automations list"),
  args: LIST_ARGS,
  run: (args, { config }) =>
    Promise.resolve(
      listAutomations(
        args.all === true ? undefined : config.blockNames,
        args.explain === true,
      ),
    ),
});
