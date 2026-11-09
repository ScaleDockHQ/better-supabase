import type { StandardSchemaV1 } from "@standard-schema/spec";

const returns = new Map<string, StandardSchemaV1>();

/** Remembers the Standard Schema a generated function result must match. */
export function registerRpcReturn(
  name: string,
  schema: StandardSchemaV1,
): void {
  returns.set(name, schema);
}

/**
 * Checks an `$rpc` result when the function's comment named a schema. A missing
 * registration leaves the value as the database returned it. The schema's
 * validate must be synchronous, which Zod and Valibot are for a plain object.
 */
export function decodeRpcReturn(name: string, value: unknown): unknown {
  const schema = returns.get(name);

  if (schema === undefined) {
    return value;
  }

  const outcome = schema["~standard"].validate(value);

  if (outcome instanceof Promise) {
    throw new TypeError(
      `${name}: the return schema must validate synchronously`,
    );
  }

  if (outcome.issues) {
    const message = outcome.issues.map((issue) => issue.message).join("; ");

    throw new TypeError(`${name}: ${message}`);
  }

  return outcome.value;
}
