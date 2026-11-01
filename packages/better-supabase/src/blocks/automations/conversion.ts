import type { StandardSchemaV1 } from "@standard-schema/spec";

import type {
  Action,
  ActionCall,
  ActionContext,
} from "../../core/automation.ts";
import type { Result } from "../../core/result.ts";

import { defineAction } from "../../core/automation.ts";
import { dbError } from "../../core/errors.ts";
import { isRecord } from "../../core/guards.ts";
import { err, ok } from "../../core/result.ts";

/** A record a conversion reads from or creates: its subject type and id. */
export interface ConversionRef {
  readonly type: string;
  readonly id: string;
}

/** The part of the relations block a conversion uses; `blocks.relations` fits. */
export interface ConversionRelations {
  link(input: {
    source: ConversionRef;
    target: ConversionRef;
    input: { readonly kind: "created_from" };
  }): PromiseLike<Result<unknown>>;
  convertedInto(input: {
    origin: ConversionRef;
    intoType: string;
  }): PromiseLike<Result<string | undefined>>;
}

/**
 * The clients every conversion gets; a conversion names the other blocks it
 * needs.
 */
export interface ConversionClients {
  readonly relations: ConversionRelations;
}

/** What a conversion's hooks receive for one action call. */
export interface ConversionContext<C> {
  readonly clients: C;
  /** The organization the event belongs to. */
  readonly tenant: string;
  readonly call: ActionCall;
  /** The record the event is about. */
  readonly source: ConversionRef;
}

/** What `defineConversionAction` takes. */
export interface ConversionSpec<C extends ConversionClients, S, T> {
  readonly kind: string;
  readonly title: string;
  readonly description?: string;
  /**
   * The subject type the action creates, such as `work_item`. A default
   * automation's `config.targetType` overrides it with the renamed type.
   */
  readonly targetType: string;
  /**
   * The record the event is about. Default: the action context's subject.
   * `undefined` skips the call.
   */
  readonly source?: (context: ActionContext) => ConversionRef | undefined;
  /**
   * The block clients for one organization, such as `createBlocks` with
   * `tenant: () => tenant` over a service connection.
   */
  readonly clients: (tenant: string) => C | PromiseLike<C>;
  /** Reads what `map` needs, such as the source record. */
  readonly load?: (context: ConversionContext<C>) => PromiseLike<Result<S>>;
  /** The target block's input schema; the mapped value must pass it. */
  readonly input?: StandardSchemaV1<T>;
  /** Turns what `load` read into the target block's input. */
  readonly map: (loaded: S, context: ConversionContext<C>) => T;
  /** Creates the target record and returns its id. */
  readonly create: (
    input: T,
    context: ConversionContext<C>,
  ) => PromiseLike<Result<{ readonly id: string }>>;
  /**
   * The target block records the `created_from` link itself, as
   * `employees.fromApplication` does.
   */
  readonly linksItself?: boolean;
}

/** What a conversion action did with one call. */
export type ConversionOutcome =
  | { readonly status: "created"; readonly target: ConversionRef }
  | { readonly status: "exists"; readonly target: ConversionRef }
  | { readonly status: "skipped" };

async function validated<T>(
  schema: StandardSchemaV1<T> | undefined,
  value: T,
): Promise<Result<T>> {
  if (schema === undefined) {
    return ok(value);
  }

  const checked = await schema["~standard"].validate(value);

  if (checked.issues === undefined) {
    return ok(checked.value);
  }

  return err(
    dbError(
      "validation",
      "The conversion's mapped input doesn't pass the target schema",
      {
        issues: checked.issues.map((issue) => ({
          message: issue.message,
          ...(issue.path === undefined
            ? {}
            : {
                path: issue.path.map((part) =>
                  typeof part === "object" ? part.key : part,
                ),
              }),
        })),
      },
    ),
  );
}

function targetTypeOf(call: ActionCall, fallback: string): string {
  const configured = call.action.config?.["targetType"];

  return typeof configured === "string" && configured !== ""
    ? configured
    : fallback;
}

/**
 * An action that turns the event's record into a record of another block, once:
 * the new record is linked `created_from` the source, so `relations.lineage`
 * finds the chain and a retried event returns the first record (`exists`).
 */
export function defineConversionAction<
  C extends ConversionClients,
  S = undefined,
  T = unknown,
>(spec: ConversionSpec<C, S, T>): Action {
  return defineAction({
    kind: spec.kind,
    title: spec.title,
    ...(spec.description === undefined
      ? {}
      : { description: spec.description }),
    run: async (call): Promise<Result<ConversionOutcome>> => {
      const { context } = call;

      const source =
        spec.source === undefined
          ? { type: context.subjectType, id: context.subjectId }
          : spec.source(context);

      if (source === undefined || source.id === "") {
        return ok({ status: "skipped" });
      }

      const tenant = context.organizationId;
      const targetType = targetTypeOf(call, spec.targetType);
      const clients = await spec.clients(tenant);

      const existing = await clients.relations.convertedInto({
        origin: source,
        intoType: targetType,
      });

      if (!existing.ok) {
        return existing;
      }

      if (existing.data !== undefined) {
        return ok({
          status: "exists",
          target: { type: targetType, id: existing.data },
        });
      }

      const hooks: ConversionContext<C> = { clients, tenant, call, source };

      // SAFETY: without `load`, `S` is left to its default `undefined`.
      const skipped = ok(undefined as S);

      const loaded = spec.load === undefined ? skipped : await spec.load(hooks);

      if (!loaded.ok) {
        return loaded;
      }

      const { map } = spec;
      const input = await validated(spec.input, map(loaded.data, hooks));

      if (!input.ok) {
        return input;
      }

      const created = await spec.create(input.data, hooks);

      if (!created.ok) {
        return created;
      }

      const target = { type: targetType, id: created.data.id };

      if (spec.linksItself !== true) {
        const linked = await clients.relations.link({
          source: target,
          target: source,
          input: { kind: "created_from" },
        });

        if (!linked.ok) {
          return linked;
        }
      }

      return ok({ status: "created", target });
    },
  });
}

function hasMethod(value: unknown, path: string): boolean {
  let at: unknown = value;

  for (const key of path.split(".")) {
    if (!isRecord(at) || !(key in at)) {
      return false;
    }

    at = at[key];
  }

  return typeof at === "function";
}

/**
 * Narrows the `clients` an action factory receives to the clients the action
 * calls: every dotted `methods` path must be a function on them. A missing one
 * throws `ACTION_CLIENTS_MISSING` for `kind`, which the dispatcher reports on
 * the action's run.
 */
export function narrowClients<C extends ConversionClients>(
  kind: string,
  methods: readonly string[],
  clients: (tenant: string) => unknown,
): (tenant: string) => Promise<C> {
  return async (tenant) => {
    const value = await clients(tenant);
    const missing = methods.filter((path) => !hasMethod(value, path));

    if (missing.length > 0) {
      throw new TypeError(
        `ACTION_CLIENTS_MISSING: ${kind} needs ${missing.join(", ")} on the clients`,
      );
    }

    // SAFETY: every method the action calls was checked on the value above.
    return value as C;
  };
}
