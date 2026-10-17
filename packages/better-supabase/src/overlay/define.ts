import type { SpecDiagnostic } from "../spec/format.ts";
import type { Reporter } from "./apply.ts";
import type {
  Extensions,
  Overlay,
  Overlay10,
  Overlay11,
  Overlay12,
  OverlayAction,
  OverlayInfo,
  OverlayVersion,
  ReusableAction,
  ReusableActionReference,
} from "./types.ts";

import { isAction, isObject, resolveReference } from "./apply.ts";
import { decodePointerToken } from "./path.ts";

/** What `defineOverlay` accepts: an Overlay document whose `overlay` field is optional. */
export type OverlayInput = {
  readonly overlay?: OverlayVersion;
  readonly info: OverlayInfo;
  readonly extends?: string;
  readonly $self?: string;
  readonly actions: readonly (OverlayAction | ReusableActionReference)[];
  readonly components?: {
    readonly actions?: Readonly<Record<string, ReusableAction>>;
  } & Extensions;
} & Extensions;

type UsesOverlay12<I extends OverlayInput> = I extends {
  readonly components: object;
}
  ? true
  : I extends { readonly $self: string }
    ? true
    : [Extract<I["actions"][number], { readonly $ref: string }>] extends [never]
      ? false
      : true;

/** The document type `defineOverlay` returns for an input. */
export type DefinedOverlay<I extends OverlayInput> = I extends {
  readonly overlay: "1.0.0";
}
  ? Overlay10
  : I extends { readonly overlay: "1.1.0" }
    ? Overlay11
    : I extends { readonly overlay: "1.2.0" }
      ? Overlay12
      : UsesOverlay12<I> extends true
        ? Overlay12
        : Overlay11;

const isReference = (
  action: OverlayAction | ReusableActionReference,
): action is ReusableActionReference => "$ref" in action;

const isPlain = (
  action: OverlayAction | ReusableActionReference,
): action is OverlayAction => !("$ref" in action);

/**
 * Defines an Overlay document with checks a schema cannot make. `overlay`
 * defaults to `1.1.0`, or to `1.2.0` when the input uses a 1.2 feature
 * (`components`, `$self` or a reusable action reference), and the return
 * type follows it.
 *
 * Throws a `TypeError` when there are no actions, when a feature needs a
 * newer version than the one set (`copy` needs 1.1, reusable actions and
 * `$self` need 1.2), when a reference names a missing reusable action, or
 * when `extends` or `$self` contains a fragment.
 *
 * @example
 * const overlay = defineOverlay({
 *   info: { title: "Public API", version: "1.0.0" },
 *   actions: [
 *     { target: "$.paths['/customers'].get", update: { summary: "List customers" } },
 *     { target: "$.paths[?@['x-internal'] == true]", remove: true },
 *   ],
 * });
 */
export function defineOverlay<const I extends OverlayInput>(
  input: I,
): DefinedOverlay<I>;
export function defineOverlay(input: OverlayInput): Overlay {
  const { overlay: declared, ...rest } = input;
  if (input.actions.length === 0) {
    throw new TypeError("defineOverlay: an overlay needs at least one action");
  }
  const references = input.actions.filter(isReference);
  const uses12 =
    input.components !== undefined ||
    input.$self !== undefined ||
    references.length > 0;
  const version = declared ?? (uses12 ? "1.2.0" : "1.1.0");
  if (version !== "1.2.0" && uses12) {
    throw new TypeError(
      `defineOverlay: reusable actions, components and $self need overlay 1.2.0, not ${version}`,
    );
  }
  if (
    version === "1.0.0" &&
    input.actions.some(
      (action) => !isReference(action) && action.copy !== undefined,
    )
  ) {
    throw new TypeError("defineOverlay: copy needs overlay 1.1.0 or later");
  }
  for (const field of ["extends", "$self"] as const) {
    if (input[field]?.includes("#")) {
      throw new TypeError(
        `defineOverlay: ${field} must not contain a fragment`,
      );
    }
  }
  const reusables = input.components?.actions ?? {};
  for (const reference of references) {
    const name = decodePointerToken(
      reference.$ref.slice("#/components/actions/".length),
    );
    if (!Object.hasOwn(reusables, name)) {
      throw new TypeError(
        `defineOverlay: ${reference.$ref} does not exist in components.actions`,
      );
    }
  }
  switch (version) {
    case "1.2.0":
      return { overlay: version, ...rest };
    case "1.1.0":
    case "1.0.0":
      return {
        overlay: version,
        ...rest,
        actions: input.actions.filter(isPlain),
      };
    default: {
      const unknown: never = version;
      throw new TypeError(
        `defineOverlay: unsupported overlay ${String(unknown)}`,
      );
    }
  }
}

/**
 * Turns an overlay into an equivalent Overlay 1.1 document for tools that do
 * not read 1.2: every reusable action reference becomes a plain action, and
 * `$self` and `components` are dropped. A reference that does not resolve is
 * left out and reported as `overlay-ref-unresolved`.
 */
export function expandReusableActions(overlay: Overlay): {
  readonly overlay: Overlay11;
  readonly diagnostics: readonly SpecDiagnostic[];
} {
  const reporter: Reporter = { prefix: "", diagnostics: [] };
  const actions: OverlayAction[] = [];
  const entries: readonly unknown[] = overlay.actions;
  for (const [index, entry] of entries.entries()) {
    if (!isObject(entry)) {
      continue;
    }
    const action =
      "$ref" in entry
        ? resolveReference(overlay, entry, `/actions/${index}`, reporter)
        : entry;
    if (action && isAction(action)) {
      actions.push(action);
    }
  }
  const extensions = Object.fromEntries(
    Object.entries(overlay).filter(([key]) => key.startsWith("x-")),
  );
  return {
    overlay: {
      overlay: "1.1.0",
      info: overlay.info,
      ...(overlay.extends === undefined ? {} : { extends: overlay.extends }),
      actions,
      ...extensions,
    },
    diagnostics: reporter.diagnostics,
  };
}
