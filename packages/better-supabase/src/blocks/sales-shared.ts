import { temporal } from "../core/temporal-required.ts";
import { optionalText } from "./shared.ts";

/** A record a sales document points at: a company, a contact, its origin. */
export interface RecordRef {
  readonly type: string;
  readonly id: string;
}

type Loose<T> = { [K in keyof T]: T[K] | undefined };

/** Drops `undefined` properties, which `exactOptionalPropertyTypes` refuses. */
export function compact<T extends object>(value: Loose<T>): T {
  // SAFETY: what is left after dropping undefined keys has the shape of T.
  return Object.fromEntries(
    Object.entries(value).filter(([, item]) => item !== undefined),
  ) as T;
}

export const plainDate = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string"
    ? temporal().PlainDate.from(value.slice(0, 10))
    : undefined;

export function refOf(type: unknown, id: unknown): RecordRef | undefined {
  const t = optionalText(type);
  const i = optionalText(id);

  return t === undefined || i === undefined ? undefined : { type: t, id: i };
}

/** Write attributes as the database reads them: dates as ISO text. */
export function attrsArg(input: object): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(input).map(([key, value]) => [
      key,
      value instanceof temporal().PlainDate ||
      value instanceof temporal().Instant
        ? value.toString()
        : value,
    ]),
  );
}
