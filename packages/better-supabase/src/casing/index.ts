import type { Casing } from "../schema/types.ts";

/** `first_name` to `firstName`. Leaves already camel-cased names untouched. */
export function toCamel(name: string): string {
  return name.replace(/_+([a-z0-9])/g, (_, char: string) => char.toUpperCase());
}

/** `firstName` to `first_name`. */
export function toSnake(name: string): string {
  return name
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .replace(/([A-Z])([A-Z][a-z])/g, "$1_$2")
    .toLowerCase();
}

export function applyCasing(name: string, casing: Casing): string {
  return casing === "camel" ? toCamel(name) : name;
}
