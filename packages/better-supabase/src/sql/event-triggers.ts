/** An event trigger a module's schema file creates. */
export interface ModuleEventTrigger {
  readonly name: string;
  /** `drop event trigger if exists` and the `create event trigger` statement. */
  readonly statement: string;
}

const CREATE_EVENT_TRIGGER =
  /^create event trigger ("?[a-z_][a-z0-9_$]*"?)\s[^;]*;/gim;

/**
 * The event triggers in a module body. They belong to no schema, so a schema
 * diff limited to some schemas (pg-delta's `-s`) leaves them out of the
 * migration; the module's data file repeats them.
 */
export function eventTriggersOf(body: string): ModuleEventTrigger[] {
  const seen = new Set<string>();
  return [...body.matchAll(CREATE_EVENT_TRIGGER)].flatMap(
    ([statement, quoted = ""]): ModuleEventTrigger[] => {
      const name = quoted.startsWith('"')
        ? quoted.slice(1, -1)
        : quoted.toLowerCase();
      if (seen.has(name)) return [];
      seen.add(name);
      return [
        {
          name,
          statement: `drop event trigger if exists ${quoted};\n${statement}`,
        },
      ];
    },
  );
}
