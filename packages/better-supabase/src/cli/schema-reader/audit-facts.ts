import type { Obj } from "./ast.ts";
import type { AuditFact } from "./facts.ts";

import { bodyOf, list, obj, str, strings } from "./ast.ts";

/** The string a literal holds, through any `::type` cast. */
function literal(node: unknown): string | undefined {
  const cast = bodyOf(node, "TypeCast");

  if (cast !== undefined) {
    return literal(cast["arg"]);
  }

  return str(obj(bodyOf(node, "A_Const")?.["sval"])["sval"]);
}

/** A `'{a,b}'` literal or `array['a', 'b']`, as names; undefined otherwise. */
function nameList(node: unknown): string[] | undefined {
  const cast = bodyOf(node, "TypeCast");

  if (cast !== undefined) {
    return nameList(cast["arg"]);
  }

  const array = bodyOf(node, "A_ArrayExpr");

  if (array !== undefined) {
    const items = list(array["elements"]).map((item) => literal(item));

    return items.every((item) => item !== undefined) ? items : undefined;
  }

  const text = literal(node);
  const inner = text === undefined ? null : /^\{(.*)\}$/s.exec(text.trim());

  return inner === null
    ? undefined
    : inner[1]!
        .split(",")
        .map((name) => name.trim().replace(/^"(.*)"$/, "$1"))
        .filter((name) => name !== "");
}

/**
 * `schema.table`, unquoted, from a regclass literal such as
 * `'public."Customers"'`.
 */
function regclassName(target: string, schema = "public"): string {
  const parts = target.match(/"(?:[^"]|"")*"|[^.]+/g) ?? [];

  const names = parts.map((part) =>
    part.startsWith('"')
      ? part.slice(1, -1).replaceAll('""', '"')
      : part.trim().toLowerCase(),
  );

  return names.length === 1 ? `${schema}.${names[0]!}` : names.join(".");
}

const POSITIONS = ["target", "ignore", "replace_trigger", "redact"] as const;

/** The call's arguments by name: positional ones take the signature's order. */
function argsOf(call: Obj): ReadonlyMap<string, unknown> {
  const named = new Map<string, unknown>();

  for (const [position, arg] of list(call["args"]).entries()) {
    const argument = bodyOf(arg, "NamedArgExpr");

    if (argument !== undefined) {
      named.set((str(argument["name"]) ?? "").toLowerCase(), argument["arg"]);
    } else if (position < POSITIONS.length) {
      named.set(POSITIONS[position]!, arg);
    }
  }

  return named;
}

/**
 * The audit registrations a top-level `select better_supabase.audit(...)` or
 * `unaudit(...)` makes. A call whose target or lists are not literals is
 * skipped.
 */
export function auditCalls(select: Obj, index: number): readonly AuditFact[] {
  return list(select["targetList"]).flatMap((item): AuditFact[] => {
    const call = bodyOf(bodyOf(item, "ResTarget")?.["val"], "FuncCall");

    if (call === undefined) {
      return [];
    }

    const name = strings(call["funcname"]).join(".");

    if (
      name !== "better_supabase.audit" &&
      name !== "better_supabase.unaudit"
    ) {
      return [];
    }

    const named = argsOf(call);
    const target = literal(named.get("target"));

    if (target === undefined) {
      return [];
    }

    if (name === "better_supabase.unaudit") {
      return [{ kind: "unregister", target: regclassName(target), index }];
    }

    const lists = (key: string): string[] | undefined =>
      named.has(key) ? nameList(named.get(key)) : [];

    const ignore = lists("ignore");
    const redact = lists("redact");

    return ignore === undefined || redact === undefined
      ? []
      : [
          {
            kind: "register",
            target: regclassName(target),
            ignore,
            redact,
            index,
          },
        ];
  });
}

/**
 * The registration a `bsb_audit` row trigger that runs
 * `better_supabase.audit_row_change('{...}')` makes, for `table`.
 */
export function auditTrigger(
  trigger: Obj,
  table: string,
  index: number,
): AuditFact | undefined {
  const name = str(trigger["trigname"]);

  if (
    (name !== "bsb_audit" && name !== "bs_audit") ||
    strings(trigger["funcname"]).join(".") !==
      "better_supabase.audit_row_change"
  ) {
    return undefined;
  }

  const first = list(trigger["args"])
    .map((arg) => str(bodyOf(arg, "String")?.["sval"]))
    .at(0);

  let settings: unknown = {};

  if (first !== undefined) {
    try {
      settings = JSON.parse(first);
    } catch {
      return undefined;
    }
  }

  if (typeof settings !== "object" || settings === null) {
    return undefined;
  }

  const names = (value: unknown): string[] =>
    Array.isArray(value)
      ? value.filter((entry): entry is string => typeof entry === "string")
      : [];

  return {
    kind: "register",
    target: table,
    ignore: "ignore" in settings ? names(settings.ignore) : [],
    redact: "redact" in settings ? names(settings.redact) : [],
    index,
  };
}

const IDENT = String.raw`(?:"(?:[^"]|"")+"|[a-z_][a-z0-9_$]*)`;
const NAME = String.raw`${IDENT}(?:\s*\.\s*${IDENT})?`;

const DO_DROP = new RegExp(
  String.raw`\bdrop\s+table\s+(?:if\s+exists\s+)?(${NAME}(?:\s*,\s*${NAME})*)\s*(?:cascade|restrict)?\s*;`,
  "gi",
);

/**
 * The tables a `do $$ ... $$` body drops with a static `drop table`, as `drop`
 * facts; a name built at run time through `execute` is not read.
 */
export function doBlockDrops(
  code: string,
  schema: string,
  index: number,
): AuditFact[] {
  return [...code.matchAll(DO_DROP)].flatMap((match) =>
    (match[1]!.match(new RegExp(NAME, "gi")) ?? []).map((name): AuditFact => ({
      kind: "drop",
      target: regclassName(name.replaceAll(/\s*\.\s*/g, "."), schema),
      index,
    })),
  );
}
