import type { SubjectsConfig } from "./types/subjects.ts";

const WIRE = /^[a-z][a-z0-9_-]{0,62}$/;

/**
 * The wire name each record type is stored and sent under: its `alias`, else
 * its key. Throws when an alias is not a type name or two types share a wire
 * name.
 */
export function recordTypeWires(
  recordTypes: SubjectsConfig,
): ReadonlyMap<string, string> {
  const wires = new Map<string, string>();
  const owners = new Map<string, string>();

  for (const [key, entry] of Object.entries(recordTypes)) {
    const wire = entry.alias ?? key;

    if (!WIRE.test(wire)) {
      throw new TypeError(
        `recordTypes.${key}.alias "${wire}" must be lowercase letters, digits, hyphens and underscores, starting with a letter`,
      );
    }

    const other = owners.get(wire);

    if (other !== undefined) {
      throw new TypeError(
        `recordTypes.${key} and recordTypes.${other} both resolve to the wire name "${wire}". Give one of them another alias.`,
      );
    }

    owners.set(wire, key);
    wires.set(key, wire);
  }

  return wires;
}

/**
 * The config with every record type keyed by its wire name and every block's
 * `on` resolved through the key or the alias, so the SQL layer sees one name.
 * Without an alias nothing changes.
 */
export function withRecordTypeAliases<
  C extends {
    readonly recordTypes?: SubjectsConfig | undefined;
    readonly blocks?: unknown;
  },
>(config: C): C {
  const recordTypes = config.recordTypes;

  if (recordTypes === undefined) {
    return config;
  }

  const wires = recordTypeWires(recordTypes);

  if (!Object.values(recordTypes).some((entry) => entry.alias !== undefined)) {
    return config;
  }

  const wireOf = (name: string): string => wires.get(name) ?? name;

  const renamed = Object.fromEntries(
    Object.entries(recordTypes).map(([key, entry]) => {
      const { alias: _alias, ...rest } = entry;

      return [wireOf(key), rest];
    }),
  );

  const listed = config.blocks;

  const blocks =
    typeof listed === "object" && listed !== null && !Array.isArray(listed)
      ? Object.fromEntries(
          Object.entries(listed).map(([name, entry]) => [
            name,
            withWireOn(entry, wireOf),
          ]),
        )
      : undefined;

  return {
    ...config,
    recordTypes: renamed,
    ...(blocks === undefined ? {} : { blocks }),
  };
}

function withWireOn<E>(entry: E, wireOf: (name: string) => string): E {
  if (typeof entry !== "object" || entry === null || !("on" in entry)) {
    return entry;
  }

  const on = entry.on;

  if (Array.isArray(on)) {
    // SAFETY: `on` of a block entry is a list of names or a keyed object.
    return { ...entry, on: on.map((name: string) => wireOf(name)) };
  }

  if (typeof on === "object" && on !== null) {
    return {
      ...entry,
      on: Object.fromEntries(
        Object.entries(on).map(([name, value]) => [wireOf(name), value]),
      ),
    };
  }

  return entry;
}
