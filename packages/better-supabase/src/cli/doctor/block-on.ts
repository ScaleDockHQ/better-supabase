import type { DoctorContext, FindingInput } from "./rules.ts";

import { isRecord } from "../guards.ts";

/**
 * The record types `on` names: list entries or object keys. A key whose entry
 * carries its own `table` registers the type inline, so it isn't counted.
 */
function namedTypes(on: unknown): readonly string[] {
  if (Array.isArray(on)) {
    return on.filter((type): type is string => typeof type === "string");
  }

  return isRecord(on)
    ? Object.entries(on)
        .filter(([, entry]) => !(isRecord(entry) && "table" in entry))
        .map(([type]) => type)
    : [];
}

const unified = (name: string): string => name.replaceAll("-", "_");

function suggestion(type: string, registered: ReadonlySet<string>): string {
  const close = [...registered].find((name) => unified(name) === unified(type));

  return close === undefined
    ? "Register it in recordTypes, or remove it from on."
    : `Did you mean "${close}"? Run \`better-supabase codemod record-types\`, or register "${type}" in recordTypes.`;
}

/**
 * Block entries whose `on` names a type `recordTypes` doesn't register. The
 * block's SQL refuses such a type when it renders, so this reports it before
 * `gen`.
 */
export function onUnknownRecordTypes(context: DoctorContext): FindingInput[] {
  const registered = new Set(Object.keys(context.config.subjects));

  return Object.entries(context.config.blocks).flatMap(([instance, entry]) =>
    namedTypes(entry?.on)
      .filter((type) => !registered.has(type))
      .map((type): FindingInput => ({
        message: `blocks.${instance}.on names "${type}", which is not a record type. ${suggestion(type, registered)}`,
        target: `blocks.${instance}.on.${type}`,
      })),
  );
}
