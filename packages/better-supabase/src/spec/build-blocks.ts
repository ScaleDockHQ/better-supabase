import type { BlockInstanceSurface, DbBlockSource } from "../core/db-blocks.ts";
import type { BuildContext } from "./build-resource.ts";
import type { JsonSchema, OperationSource } from "./model.ts";
import type { ApiOptions, BlockApiDescription } from "./options.ts";
import type { StandardLike } from "./schemas.ts";

import { isPlainObject } from "../core/clone.ts";
import { instanceProperty } from "../core/instance-property.ts";
import { jsonContent, jsonResponse } from "./build-resource.ts";

/** The contract verbs that only read, so `requirePermissions` skips them. */
export const READ_VERBS: ReadonlySet<string> = new Set([
  "list",
  "page",
  "get",
  "count",
  "aggregate",
]);

const VERB_STATUSES: readonly number[] = [400, 401, 403, 404, 409, 422];

function isStandard(value: unknown): value is StandardLike {
  return isPlainObject(value) && isPlainObject(value["~standard"]);
}

/** Every verb of an instance: its methods, then `member.method`. */
function instanceVerbs(surface: BlockInstanceSurface): string[] {
  return [
    ...surface.methods,
    ...Object.entries(surface.members).flatMap(([member, methods]) =>
      methods.map((method) => `${member}.${method}`),
    ),
  ];
}

/**
 * The body schema of `create` and `list` when the block has one entity with
 * that schema; any other verb takes its arguments as documented on the client.
 */
function inputOf(
  surface: BlockInstanceSurface,
  verb: string,
): StandardLike | undefined {
  const field =
    verb === "create" ? "input" : verb === "list" ? "listFilter" : undefined;

  if (field === undefined) {
    return undefined;
  }

  const found = Object.values(surface.schemas).flatMap((entity) => {
    const schema = entity[field];

    return isStandard(schema) ? [schema] : [];
  });

  return found.length === 1 ? found[0] : undefined;
}

/** The block instances `options.blocks` publishes, with their descriptions. */
export function publishedBlocks<Ref>(
  source: DbBlockSource | undefined,
  input: ApiOptions<Ref>["blocks"],
): Readonly<Record<string, BlockApiDescription<Ref>>> {
  if (input === false || source === undefined) {
    return {};
  }

  if (input === undefined) {
    return Object.fromEntries(source.instances.map((key) => [key, {}]));
  }

  return Object.fromEntries(
    Object.entries(input).map(([key, entry]) => [
      key,
      entry === true ? {} : entry,
    ]),
  );
}

/** Adds `POST /<instance>/<verb>` for each published block instance. */
export function buildBlocks<Ref>(
  ctx: BuildContext<Ref>,
  source: DbBlockSource | undefined,
  input: ApiOptions<Ref>["blocks"],
): void {
  if (source === undefined) {
    return;
  }

  for (const [key, description] of Object.entries(
    publishedBlocks(source, input),
  )) {
    if (!source.instances.includes(key)) {
      ctx.report({
        code: "block-unknown",
        severity: "error",
        message: `blocks.${key} names no block instance of betterSupabase.blocks()`,
      });
      continue;
    }

    const surface = source.describe?.(key);

    if (!surface) {
      ctx.report({
        code: "block-undescribed",
        severity: "warning",
        message: `The ${key} block instance can't list its methods, so the API leaves it out`,
      });
      continue;
    }

    buildInstance(ctx, key, surface, description);
  }
}

function buildInstance<Ref>(
  ctx: BuildContext<Ref>,
  key: string,
  surface: BlockInstanceSurface,
  description: BlockApiDescription<Ref>,
): void {
  const {
    options,
    prefix,
    base,
    globalErrors,
    operations,
    report,
    addTag,
    keyOf,
    schemaOf,
    usedErrors,
  } = ctx;

  const available = instanceVerbs(surface);
  const verbs = description.verbs ?? available;
  const tag = description.tag ?? key;
  const property = instanceProperty(key);
  const collection = `${base}${description.path ?? `/${key}`}`;

  addTag(tag, description.description);

  for (const verb of verbs) {
    if (!available.includes(verb)) {
      report({
        code: "block-verb-unknown",
        severity: "error",
        message: `blocks.${key}.verbs: the ${surface.block} client has no ${verb} method`,
      });
      continue;
    }

    const [first, second] = verb.split(".");
    const member = second === undefined ? undefined : first;
    const method = second ?? first ?? verb;

    const source: OperationSource = {
      kind: "verb",
      owner: "block",
      name: key,
      ...(member === undefined ? {} : { member }),
      verb: method,
    };

    const path = `${collection}/${verb.replaceAll(".", "/")}`;
    const defaultId = `${property}.${verb}`;

    const id =
      options.operationId?.({ source, method: "post", path, defaultId }) ??
      defaultId;

    const ref = description.permissions?.[verb];

    const permission =
      ref === undefined ? undefined : keyOf(ref, `blocks.${key}.${verb}`);

    const standard = inputOf(surface, verb);

    const body: JsonSchema = standard
      ? schemaOf(standard, "input", "input", id)
      : {};

    operations.push({
      id,
      method: "post",
      path,
      tags: [tag],
      source,
      summary: `${verb} (${key})`,
      description: `Calls \`db.${property}.${verb}()\`. A method that takes more than one argument takes them as a JSON array.`,
      parameters: [],
      requestBody: { required: false, content: jsonContent(body) },
      responses: {
        "200": jsonResponse({}, "What the method returns."),
        ...usedErrors(globalErrors, VERB_STATUSES, permission !== undefined),
      },
      extensions: {
        [`${prefix}block`]: surface.block,
        [`${prefix}instance`]: key,
        [`${prefix}verb`]: verb,
        ...(permission === undefined
          ? {}
          : { [`${prefix}permission`]: permission }),
      },
      ...(permission === undefined ? {} : { permission }),
      ...(description.security ? { security: description.security } : {}),
    });
  }
}
