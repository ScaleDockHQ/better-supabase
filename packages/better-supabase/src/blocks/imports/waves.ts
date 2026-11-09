/** An import entity and the entities that have to finish first. */
export interface ImportWaveTarget {
  readonly entity: string;
  readonly dependsOn?: readonly string[];
}

/**
 * Orders entities into waves. Independent entities share a wave. A cycle
 * throws. `unordered` keeps the input order as one wave.
 */
export function importWaves(
  targets: readonly ImportWaveTarget[],
  options: { readonly unordered?: boolean } = {},
): readonly (readonly string[])[] {
  if (options.unordered === true) {
    return [targets.map((target) => target.entity)];
  }

  const names = targets.map((target) => target.entity);
  const known = new Set(names);
  const deps = new Map<string, readonly string[]>();

  for (const target of targets) {
    const edges = (target.dependsOn ?? []).filter((name) => known.has(name));

    if (edges.includes(target.entity)) {
      throw new TypeError(`import entity "${target.entity}" depends on itself`);
    }

    deps.set(target.entity, edges);
  }

  const placed = new Set<string>();
  const waves: string[][] = [];

  while (placed.size < names.length) {
    const wave = names.filter(
      (name) =>
        !placed.has(name) &&
        (deps.get(name) ?? []).every((edge) => placed.has(edge)),
    );

    if (wave.length === 0) {
      throw new TypeError("import entities have a dependency cycle");
    }

    waves.push(wave);

    for (const name of wave) {
      placed.add(name);
    }
  }

  return waves;
}
