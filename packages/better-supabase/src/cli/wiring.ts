import { dirname, join } from "node:path";

import type {
  BlockEnvKey,
  BlockProvider,
  BlockWorker,
} from "../blocks/index.ts";
import type { ResolvedConfig } from "../config/index.ts";
import type { PresetCatalog, PresetCatalogManifest } from "../preset/index.ts";
import type { PlannedFile } from "./core/files.ts";
import type { TemplateContext } from "./templates.ts";

import { PRESET_CATALOG } from "../preset/index.ts";
import { importFrom } from "./templates.ts";

/** One block instance to wire: its key in `blocks.generated.ts` and its block. */
export interface WiringInstance {
  readonly name: string;
  readonly block: string;
}

export interface WiringEnv extends BlockEnvKey {
  /** The blocks that read it. */
  readonly blocks: readonly string[];
}

export interface WiringProvider {
  readonly instance: string;
  readonly block: string;
  readonly provider: BlockProvider;
}

export interface WiringWorker extends BlockWorker {
  readonly block: string;
}

type ActionDescriptor = NonNullable<PresetCatalogManifest["actions"]>[number];

type BlockSchedule = NonNullable<PresetCatalogManifest["schedules"]>[number];

export interface WiringAction extends ActionDescriptor {
  readonly block: string;
}

export interface WiringSchedule extends BlockSchedule {
  readonly block: string;
}

/** What the installed blocks need from the app, deduplicated. */
export interface WiringPlan {
  readonly env: readonly WiringEnv[];
  readonly providers: readonly WiringProvider[];
  readonly workers: readonly WiringWorker[];
  /** The action kinds to register in the rules consumer's action registry. */
  readonly actions: readonly WiringAction[];
  /** The block timers to schedule on the queue. */
  readonly schedules: readonly WiringSchedule[];
}

/** The config's instances, by the key `blocks.generated.ts` gives them. */
export function configInstances(
  config: Pick<ResolvedConfig, "instances">,
): WiringInstance[] {
  return Object.entries(config.instances).map(([name, instance]) => ({
    name,
    block: instance.block,
  }));
}

/** The manifest that installs `block`, a block or one of its SQL modules. */
function manifestOf(
  block: string,
  catalog: PresetCatalog = PRESET_CATALOG,
): PresetCatalogManifest | undefined {
  return (
    catalog.manifests.find((manifest) => manifest.name === block) ??
    catalog.manifests.find((manifest) => manifest.sql.includes(block))
  );
}

/** The env keys, providers, workers, actions and timers `instances` need. */
export function wiringFor(
  instances: readonly WiringInstance[],
  catalog: PresetCatalog = PRESET_CATALOG,
): WiringPlan {
  const env = new Map<string, { entry: BlockEnvKey; blocks: string[] }>();
  const providers: WiringProvider[] = [];
  const workers = new Map<string, WiringWorker>();
  const actions = new Map<string, WiringAction>();
  const schedules = new Map<string, WiringSchedule>();

  for (const instance of instances) {
    const manifest = manifestOf(instance.block, catalog);

    if (manifest === undefined) {
      continue;
    }

    for (const entry of manifest.env ?? []) {
      const seen = env.get(entry.key);

      if (seen === undefined) {
        env.set(entry.key, { entry, blocks: [manifest.name] });
      } else {
        if (!seen.blocks.includes(manifest.name)) {
          seen.blocks.push(manifest.name);
        }

        if (entry.required !== false && seen.entry.required === false) {
          seen.entry = entry;
        }
      }
    }

    for (const provider of manifest.providers ?? []) {
      providers.push({
        instance: instance.name,
        block: manifest.name,
        provider,
      });
    }

    for (const worker of manifest.workers ?? []) {
      if (!workers.has(worker.name)) {
        workers.set(worker.name, { ...worker, block: manifest.name });
      }
    }

    for (const action of manifest.actions ?? []) {
      if (!actions.has(action.kind)) {
        actions.set(action.kind, { ...action, block: manifest.name });
      }
    }

    for (const schedule of manifest.schedules ?? []) {
      schedules.set(`${manifest.name}.${schedule.name}`, {
        ...schedule,
        block: manifest.name,
      });
    }
  }

  return {
    env: [...env.values()].map(({ entry, blocks }) => ({ ...entry, blocks })),
    providers,
    workers: [...workers.values()],
    actions: [...actions.values()],
    schedules: [...schedules.values()],
  };
}

const ENV_HEADER = "# better-supabase blocks";

/**
 * `current` with the keys of `env` it lacks appended, each under its
 * description, or `current` itself when every key is there.
 */
export function envExampleText(
  current: string | undefined,
  env: readonly WiringEnv[],
): string {
  const text = current ?? "";

  const has = (key: string): boolean =>
    new RegExp(`^\\s*(?:export\\s+)?${key}\\s*=`, "m").test(text);

  const missing = env.filter((entry) => !has(entry.key));

  if (missing.length === 0) {
    return text;
  }

  const lines = missing.flatMap((entry) => [
    `# ${entry.description}${entry.required === false ? " Optional." : ""} (${entry.blocks.join(", ")})`,
    `${entry.key}=`,
  ]);

  const head =
    text.length === 0 ? "" : text.endsWith("\n") ? `${text}\n` : `${text}\n\n`;

  return `${head}${text.includes(ENV_HEADER) ? "" : `${ENV_HEADER}\n`}${lines.join("\n")}\n`;
}

/** `providers.ts`, next to `blocks.generated.ts`. */
function providersPath(context: TemplateContext): string {
  return join(dirname(context.generated), "providers.ts");
}

const PROVIDERS_END = "} satisfies Partial<typeof blocks>;";

const propertyKey = (name: string): string =>
  /^[A-Za-z_$][\w$]*$/.test(name) ? name : JSON.stringify(name);

const accessor = (name: string): string =>
  /^[A-Za-z_$][\w$]*$/.test(name)
    ? `blocks.${name}`
    : `blocks[${JSON.stringify(name)}]`;

/**
 * The commented stub for one provider. It stays a comment so the app picks the
 * implementation; doctor's BS505 fails while a required one is unwired.
 */
function providerStub(entry: WiringProvider): string[] {
  const { provider } = entry;

  return [
    `  // ${entry.instance}${provider.required ? " (required)" : ""}: ${provider.description}`,
    `  // \`${provider.option}\` takes an implementation of ${provider.type} from "${provider.from}".`,
    `  // ${propertyKey(entry.instance)}: ${accessor(entry.instance)}.with({ ${provider.option}: ${provider.example} }),`,
  ];
}

const stubbed = (text: string, entry: WiringProvider): boolean =>
  text.includes(
    `${propertyKey(entry.instance)}: ${accessor(entry.instance)}.with({ ${entry.provider.option}:`,
  );

/** A new `providers.ts` with a stub for each of `providers`. */
export function providersSource(
  context: TemplateContext,
  providers: readonly WiringProvider[],
): string {
  const path = providersPath(context);

  const generated = importFrom(
    context,
    path,
    join(dirname(context.generated), "blocks.generated.ts"),
  );

  return [
    `import { blocks } from "${generated}";`,
    "",
    "/**",
    " * The providers the installed blocks take. Spread them over the generated",
    " * blocks: `defineBlocks(blockConfig, { ...blocks, ...providers })`.",
    " * `better-supabase add` appends a commented stub for each block that takes",
    " * one, and doctor (BS505) fails while a required one is still a comment.",
    " */",
    "export const providers = {",
    ...providers.flatMap(providerStub),
    PROVIDERS_END,
    "",
  ].join("\n");
}

export type ProvidersEdit =
  | { readonly ok: true; readonly text: string }
  | { readonly ok: false; readonly reason: string };

/** `current` with stubs for the providers it doesn't mention yet. */
export function addProviderStubs(
  current: string,
  providers: readonly WiringProvider[],
): ProvidersEdit {
  const missing = providers.filter((entry) => !stubbed(current, entry));

  if (missing.length === 0) {
    return { ok: true, text: current };
  }

  const end = current.lastIndexOf(PROVIDERS_END);

  if (end === -1) {
    return { ok: false, reason: `it has no \`${PROVIDERS_END}\`` };
  }

  return {
    ok: true,
    text: `${current.slice(0, end)}${missing.flatMap(providerStub).join("\n")}\n${current.slice(end)}`,
  };
}

/**
 * The files the wiring writes: `.env.example` with the missing keys, and
 * `providers.ts` with the missing stubs. `read` returns a file's contents
 * relative to the project root, or `undefined`.
 */
export async function wiringFiles(
  context: TemplateContext,
  plan: WiringPlan,
  read: (path: string) => Promise<string | undefined>,
): Promise<{ files: PlannedFile[]; notes: string[] }> {
  const files: PlannedFile[] = [];
  const notes: string[] = [];

  if (plan.env.length > 0) {
    const current = await read(".env.example");
    const text = envExampleText(current, plan.env);

    if (text !== (current ?? "")) {
      files.push({
        path: ".env.example",
        contents: text,
        policy: current === undefined ? "generated" : "edit",
      });
    }
  }

  if (plan.providers.length > 0) {
    const path = providersPath(context);
    const current = await read(path);

    if (current === undefined) {
      files.push({
        path,
        contents: providersSource(context, plan.providers),
        policy: "generated",
      });
    } else {
      const edit = addProviderStubs(current, plan.providers);

      if (!edit.ok) {
        notes.push(
          `Add the provider stubs to ${path} by hand (${edit.reason}):`,
          ...plan.providers.flatMap(providerStub),
        );
      } else if (edit.text !== current) {
        files.push({ path, contents: edit.text, policy: "edit" });
      }
    }
  }

  return { files, notes };
}

/** The numbered steps left after the wiring is written. */
export function wiringChecklist(
  context: TemplateContext,
  plan: WiringPlan,
  glue: string | undefined,
): string[] {
  const steps: string[] = [];
  const required = plan.env.filter((entry) => entry.required !== false);

  if (required.length > 0) {
    steps.push(
      `Set ${required.map((entry) => entry.key).join(", ")} in .env.local and in every deployed environment (.env.example lists them).`,
    );
  }

  if (glue !== undefined) {
    steps.push(`Install the routes: ${glue}`);
  }

  for (const worker of plan.workers) {
    steps.push(
      worker.path === undefined
        ? `Run the ${worker.name} worker (${worker.block}): ${worker.description}`
        : `Call ${worker.path} ${worker.schedule === undefined ? "from a cron" : `on the cron \`${worker.schedule}\``} with \`Authorization: Bearer $CRON_SECRET\` (${worker.block}: ${worker.description})`,
    );
  }

  if (plan.schedules.length > 0) {
    steps.push(
      `Schedule the block timers (${plan.schedules.map((entry) => `${entry.block} ${entry.runs} at \`${entry.cron}\``).join(", ")}): call \`jobs.ensureSchedules(blockSchedules(blocks), { prefix: BLOCK_SCHEDULE_PREFIX })\` once and drain the \`block_ticks\` queue with \`blockTickHandler\`.`,
    );
  }

  if (plan.actions.length > 0) {
    steps.push(
      `Register the actions in the rules consumer's \`createActionRegistry\`: ${plan.actions.map((entry) => `${entry.kind} (${entry.block})`).join(", ")}.`,
    );
  }

  const providers = plan.providers.filter((entry) => entry.provider.required);

  if (providers.length > 0) {
    steps.push(
      `Fill in the provider for ${providers.map((entry) => entry.instance).join(", ")} in ${providersPath(context)}, and spread \`...providers\` into \`defineBlocks\`.`,
    );
  }

  return steps.map((step, index) => `  ${index + 1}. ${step}`);
}
