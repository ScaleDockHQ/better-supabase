import type { ImportWaveTarget } from "./waves.ts";

import { importWaves } from "./waves.ts";

/** One staged row of a multi-entity source. */
export interface SourceItem {
  readonly key: string;
  readonly data: Readonly<Record<string, unknown>>;
  readonly refs?: Readonly<Record<string, string>>;
  readonly sourceUpdatedAt?: string;
}

/** What a preview shows before a run starts. */
export interface ImportDescription {
  readonly entities: readonly string[];
  readonly counts: Readonly<Record<string, number>>;
  readonly warnings: readonly string[];
}

/** A file or system that yields many entities. */
export interface ImportSource<Input> {
  readonly id: string;
  readonly read: (
    input: Input,
  ) => Promise<Readonly<Record<string, readonly SourceItem[]>>>;
  readonly map: (
    staged: Readonly<Record<string, readonly SourceItem[]>>,
  ) => Readonly<Record<string, readonly SourceItem[]>>;
  readonly describe: (
    staged: Readonly<Record<string, readonly SourceItem[]>>,
  ) => ImportDescription;
  readonly dependencies?: readonly ImportWaveTarget[];
}

export interface ImportSourceClient {
  start: (
    source: string,
    options: { readonly dryRun: boolean },
  ) => Promise<{ readonly id: string }>;
  upsert: (
    run: string,
    entity: string,
    items: readonly SourceItem[],
  ) => Promise<void>;
  finish: (run: string) => Promise<void>;
}

export interface ImportSourceRun {
  readonly dryRun: boolean;
  readonly description: ImportDescription;
  readonly waves: readonly (readonly string[])[];
  readonly runId?: string;
}

/** Registers a multi-entity source. */
export function defineImportSource<Input>(
  source: ImportSource<Input>,
): ImportSource<Input> {
  return source;
}

/**
 * Reads, maps and describes a source. A dry run stops there. A real run writes
 * each wave through the client.
 */
export async function runImportSource<Input>(
  source: ImportSource<Input>,
  input: Input,
  options: { readonly client: ImportSourceClient; readonly dryRun?: boolean },
): Promise<ImportSourceRun> {
  const staged = source.map(await source.read(input));
  const description = source.describe(staged);

  const waves = importWaves(
    source.dependencies ?? description.entities.map((entity) => ({ entity })),
  );

  if (options.dryRun === true) {
    return { dryRun: true, description, waves };
  }

  const started = await options.client.start(source.id, { dryRun: false });

  for (const wave of waves) {
    for (const entity of wave) {
      const items = staged[entity] ?? [];

      if (items.length > 0) {
        await options.client.upsert(started.id, entity, items);
      }
    }
  }

  await options.client.finish(started.id);

  return { dryRun: false, description, waves, runId: started.id };
}
