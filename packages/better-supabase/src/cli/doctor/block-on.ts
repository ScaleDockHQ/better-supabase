import type { DoctorContext, FindingInput } from "./rules.ts";

import { isRecord } from "../guards.ts";

/** The record types `on` names: list entries or object keys. */
function namedTypes(on: unknown): readonly string[] {
  if (Array.isArray(on)) {
    return on.filter((type): type is string => typeof type === "string");
  }

  return isRecord(on) ? Object.keys(on) : [];
}

/**
 * Block entries whose `on` names a type `config.subjects` doesn't register. The
 * block's SQL refuses such a type when it renders, so this reports it before
 * `gen`.
 */
export function onUnknownRecordTypes(context: DoctorContext): FindingInput[] {
  const registered = new Set(Object.keys(context.config.subjects));

  return Object.entries(context.config.blocks).flatMap(([instance, entry]) =>
    namedTypes(entry?.on)
      .filter((type) => !registered.has(type))
      .map((type): FindingInput => ({
        message: `blocks.${instance}.on names "${type}", which is not a record type. Register it in config.subjects, or remove it from on.`,
        target: `blocks.${instance}.on.${type}`,
      })),
  );
}
