import type { ScanToken } from "@supabase/pg-parser";

import type { Obj } from "./ast.ts";
import type {
  AlterFact,
  AuditFact,
  CallFact,
  CheckFact,
  ColumnFact,
  CommentFact,
  DeclaredFact,
  DropFact,
  DropKind,
  EnumFact,
  FileFacts,
  ForeignKeyFact,
  FunctionFact,
  GrantFact,
  IndexFact,
  KeyFact,
  MarkerFact,
  ObjectFact,
  PolicyFact,
  TableFact,
  TriggerFact,
  ViewFact,
} from "./facts.ts";
import type { Source } from "./source.ts";

import { bodyOf, columnRefs, list, obj, str, strings, unwrap } from "./ast.ts";
import { auditCalls, auditTrigger } from "./audit-facts.ts";
import { commentOf } from "./comment-facts.ts";
import { parenthesized, topLevelParts } from "./source.ts";
import { TRIGGER_EVENTS, callsOf, hasBit, timingOf } from "./trigger-facts.ts";
import { blocksWrites, selectNames } from "./view-shape.ts";

/** Tokens that end a column's type: the first option, or the end of the part. */
const TYPE_END = new Set([
  "NOT",
  "NULL_P",
  "DEFAULT",
  "CONSTRAINT",
  "CHECK",
  "UNIQUE",
  "PRIMARY",
  "REFERENCES",
  "GENERATED",
  "COLLATE",
]);

function matchOf(type: string | undefined): ForeignKeyFact["match"] {
  if (type === "f") {
    return "full";
  }

  return type === "p" ? "partial" : "simple";
}

const ACTION: Readonly<Record<string, string>> = {
  a: "no action",
  r: "restrict",
  c: "cascade",
  n: "set null",
  d: "set default",
};

interface Context {
  readonly source: Source;
  /** The first schema of the last `set search_path`, else `public`. */
  schema: string;
  index: number;
}

function nonEmpty(value: string | undefined): string | undefined {
  return value === "" ? undefined : value;
}

function qualify(context: Context, relation: Obj): string {
  const schema = str(relation["schemaname"]);

  return `${schema === undefined || schema === "" ? context.schema : schema}.${str(relation["relname"]) ?? ""}`;
}

function qualifiedNames(context: Context, names: readonly string[]): string {
  return names.length > 1
    ? `${names.at(-2)!}.${names.at(-1)!}`
    : `${context.schema}.${names[0] ?? ""}`;
}

/** The type of a column as written, read from the tokens at `location`. */
function typeText(
  source: Source,
  location: number,
  stops: ReadonlySet<string>,
): string {
  const tokens = source.tokens;
  const first = source.tokenAt(location);
  const taken: ScanToken[] = [];
  let depth = 0;

  for (let at = first; at < tokens.length; at += 1) {
    const token = tokens[at]!;

    if (
      depth === 0 &&
      (stops.has(token.kind) || token.text === "," || token.text === ";")
    ) {
      break;
    }

    if (token.text === "(" || token.text === "[") {
      depth += 1;
    } else if (token.text === ")" || token.text === "]") {
      depth -= 1;

      if (depth < 0) {
        break;
      }
    }

    taken.push(token);
  }

  return source.render(taken);
}

/** The tokens after the column name, up to the comma that ends the column. */
function definitionText(source: Source, location: unknown): string {
  if (typeof location !== "number") {
    return "";
  }

  const tokens = source.tokens;
  const taken: ScanToken[] = [];
  let depth = 0;

  for (let at = source.tokenAt(location) + 1; at < tokens.length; at += 1) {
    const token = tokens[at]!;

    if (depth === 0 && (token.text === "," || token.text === ";")) {
      break;
    }

    if (token.text === "(" || token.text === "[") {
      depth += 1;
    } else if (token.text === ")" || token.text === "]") {
      depth -= 1;

      if (depth < 0) {
        break;
      }
    }

    taken.push(token);
  }

  return source.raw(taken);
}

function columnOf(source: Source, definition: Obj): ColumnFact {
  const typeName = obj(definition["typeName"]);

  const constraints = list(definition["constraints"]).flatMap((item) => {
    const body = bodyOf(item, "Constraint");

    return body === undefined ? [] : [body];
  });

  const kinds = new Set(constraints.map((each) => str(each["contype"])));
  const location = typeName["location"];

  return {
    name: str(definition["colname"]) ?? "",
    type:
      typeof location === "number" ? typeText(source, location, TYPE_END) : "",
    notNull:
      definition["is_not_null"] === true ||
      kinds.has("CONSTR_NOTNULL") ||
      kinds.has("CONSTR_PRIMARY"),
    hasDefault: kinds.has("CONSTR_DEFAULT") || kinds.has("CONSTR_IDENTITY"),
    definition: definitionText(source, definition["location"]),
  };
}

function foreignKeyOf(
  context: Context,
  constraint: Obj,
  column: string | undefined,
): ForeignKeyFact {
  const attrs = strings(constraint["fk_attrs"]);

  return {
    name: nonEmpty(str(constraint["conname"])),
    columns: attrs.length === 0 && column !== undefined ? [column] : attrs,
    references: qualify(context, obj(constraint["pktable"])),
    referencedColumns: strings(constraint["pk_attrs"]),
    deferrable: constraint["deferrable"] === true,
    initiallyDeferred: constraint["initdeferred"] === true,
    match: matchOf(str(constraint["fk_matchtype"])),
    onDelete: ACTION[str(constraint["fk_del_action"]) ?? "a"] ?? "no action",
    onUpdate: ACTION[str(constraint["fk_upd_action"]) ?? "a"] ?? "no action",
  };
}

function checkOf(
  source: Source,
  constraint: Obj,
  column: string | undefined,
): CheckFact {
  const columns = columnRefs(constraint["raw_expr"]);
  const location = constraint["location"];
  const tokens = typeof location === "number" ? source.tokens : [];

  const check = tokens.findIndex(
    (token) =>
      token.kind === "CHECK" &&
      token.start >= (typeof location === "number" ? location : 0),
  );

  const range = check === -1 ? undefined : parenthesized(tokens, check);

  return {
    name: nonEmpty(str(constraint["conname"])),
    columns: columns.length === 0 && column !== undefined ? [column] : columns,
    expression:
      range === undefined
        ? ""
        : source.render(tokens.slice(range[0] + 1, range[1])),
  };
}

interface TableParts {
  readonly columns: ColumnFact[];
  readonly primaryKey: string[];
  readonly keys: KeyFact[];
  readonly foreignKeys: ForeignKeyFact[];
  readonly checks: CheckFact[];
  columnsElsewhere: boolean;
}

function addConstraint(
  context: Context,
  parts: TableParts,
  constraint: Obj,
  column: string | undefined,
): void {
  switch (str(constraint["contype"]) ?? "") {
    case "CONSTR_PRIMARY": {
      const keys = strings(constraint["keys"]);

      const columns = keys.length === 0 && column ? [column] : keys;

      parts.primaryKey.push(...columns);
      parts.keys.push({ columns, primary: true, nullsNotDistinct: false });

      break;
    }

    case "CONSTR_UNIQUE": {
      const keys = strings(constraint["keys"]);

      parts.keys.push({
        columns: keys.length === 0 && column ? [column] : keys,
        primary: false,
        nullsNotDistinct: constraint["nulls_not_distinct"] === true,
      });

      break;
    }

    case "CONSTR_FOREIGN": {
      parts.foreignKeys.push(foreignKeyOf(context, constraint, column));

      break;
    }

    case "CONSTR_CHECK": {
      parts.checks.push(checkOf(context.source, constraint, column));

      break;
    }

    default: {
      break;
    }
  }
}

function tableOf(
  context: Context,
  create: Obj,
  line: number,
  asSelect: boolean,
): TableFact {
  const relation = obj(create["relation"]);
  const persistence = str(relation["relpersistence"]);

  const parts: TableParts = {
    columns: [],
    primaryKey: [],
    keys: [],
    foreignKeys: [],
    checks: [],
    columnsElsewhere: asSelect,
  };

  for (const element of list(create["tableElts"])) {
    const definition = bodyOf(element, "ColumnDef");

    if (definition !== undefined) {
      parts.columns.push(columnOf(context.source, definition));

      let previous: string | undefined;

      for (const item of list(definition["constraints"])) {
        const constraint = bodyOf(item, "Constraint");

        if (constraint === undefined) {
          continue;
        }

        const type = str(constraint["contype"]);

        // A column's `deferrable` and `initially` are their own nodes after the
        // `references` they modify, in either order.
        if (previous === "CONSTR_FOREIGN" && type?.startsWith("CONSTR_ATTR_")) {
          if (
            type === "CONSTR_ATTR_DEFERRABLE" ||
            type === "CONSTR_ATTR_DEFERRED"
          ) {
            const key = parts.foreignKeys.pop()!;

            parts.foreignKeys.push({
              ...key,
              deferrable: true,
              initiallyDeferred:
                key.initiallyDeferred || type === "CONSTR_ATTR_DEFERRED",
            });
          }

          continue;
        }

        previous = type;
        addConstraint(context, parts, constraint, str(definition["colname"]));
      }

      continue;
    }

    const constraint = bodyOf(element, "Constraint");

    if (constraint !== undefined) {
      addConstraint(context, parts, constraint, undefined);
    } else if (bodyOf(element, "TableLikeClause") !== undefined) {
      parts.columnsElsewhere = true;
    }
  }

  const inherits = list(create["inhRelations"]).flatMap((item) => {
    const body = bodyOf(item, "RangeVar");

    return body === undefined ? [] : [qualify(context, body)];
  });

  return {
    name: qualify(context, relation),
    line,
    index: context.index,
    ifNotExists: create["if_not_exists"] === true,
    temporary: persistence === "t",
    unlogged: persistence === "u",
    partitionOf: inherits[0],
    columnsElsewhere: parts.columnsElsewhere,
    columns: parts.columns,
    primaryKey: parts.primaryKey,
    keys: parts.keys,
    foreignKeys: parts.foreignKeys,
    checks: parts.checks,
  };
}

const DROP_KINDS: Readonly<Record<string, DropKind>> = {
  OBJECT_TABLE: "table",
  OBJECT_VIEW: "view",
  OBJECT_MATVIEW: "view",
  OBJECT_INDEX: "index",
  OBJECT_TYPE: "type",
  OBJECT_DOMAIN: "type",
  OBJECT_FUNCTION: "function",
  OBJECT_PROCEDURE: "function",
  OBJECT_POLICY: "policy",
  OBJECT_TRIGGER: "trigger",
};

function dropsOf(context: Context, drop: Obj): readonly DropFact[] {
  const kind = DROP_KINDS[str(drop["removeType"]) ?? ""] ?? "other";

  return list(drop["objects"]).flatMap((item) => {
    const unwrapped = unwrap(item);

    const names =
      unwrapped?.[0] === "List"
        ? strings(unwrapped[1]["items"])
        : unwrapped?.[0] === "TypeName"
          ? strings(unwrapped[1]["names"])
          : unwrapped?.[0] === "ObjectWithArgs"
            ? strings(unwrapped[1]["objname"])
            : [];

    if (names.length === 0) {
      return [];
    }

    // A policy or trigger drop names the table first and the object last.
    const name =
      kind === "policy" || kind === "trigger"
        ? `${qualifiedNames(context, names.slice(0, -1))}.${names.at(-1)!}`
        : qualifiedNames(context, names);

    return [{ kind, name, index: context.index }];
  });
}

function alterOf(context: Context, alter: Obj, line: number): AlterFact {
  const added: ColumnFact[] = [];
  const addedIfNotExists: string[] = [];
  const setNotNull: string[] = [];
  const dropNotNull: string[] = [];
  const dropped: string[] = [];
  const foreignKeys: ForeignKeyFact[] = [];
  const checks: CheckFact[] = [];
  let enablesRls = false;

  for (const item of list(alter["cmds"])) {
    const command = bodyOf(item, "AlterTableCmd");

    if (command === undefined) {
      continue;
    }

    const name = str(command["name"]) ?? "";

    switch (str(command["subtype"]) ?? "") {
      case "AT_AddColumn": {
        const definition = bodyOf(command["def"], "ColumnDef");

        if (definition !== undefined) {
          const column = columnOf(context.source, definition);

          added.push(column);

          if (command["missing_ok"] === true) {
            addedIfNotExists.push(column.name);
          }
        }

        break;
      }

      case "AT_SetNotNull": {
        setNotNull.push(name);

        break;
      }

      case "AT_DropNotNull": {
        dropNotNull.push(name);

        break;
      }

      case "AT_DropColumn": {
        dropped.push(name);

        break;
      }

      case "AT_AddConstraint": {
        const constraint = bodyOf(command["def"], "Constraint");

        if (constraint === undefined) {
          break;
        }

        if (str(constraint["contype"]) === "CONSTR_FOREIGN") {
          foreignKeys.push(foreignKeyOf(context, constraint, undefined));
        } else if (str(constraint["contype"]) === "CONSTR_CHECK") {
          checks.push(checkOf(context.source, constraint, undefined));
        }

        break;
      }

      case "AT_EnableRowSecurity": {
        enablesRls = true;

        break;
      }

      default: {
        break;
      }
    }
  }

  return {
    table: qualify(context, obj(alter["relation"])),
    line,
    index: context.index,
    addedColumns: added,
    addedIfNotExists,
    setNotNull,
    dropNotNull,
    droppedColumns: dropped,
    addedForeignKeys: foreignKeys,
    addedChecks: checks,
    enablesRls,
  };
}

function roleNames(value: unknown): readonly string[] {
  return list(value).flatMap((item) => {
    const role = bodyOf(item, "RoleSpec");

    const name =
      role?.["roletype"] === "ROLESPEC_PUBLIC"
        ? "public"
        : nonEmpty(str(role?.["rolename"]));

    return name === undefined ? [] : [name];
  });
}

/** The text of `using (...)` or `with check (...)`, as written. */
function clauseText(
  source: Source,
  tokens: readonly ScanToken[],
  words: readonly string[],
): string | undefined {
  for (let at = 0; at < tokens.length; at += 1) {
    const matches = words.every(
      (word, offset) => tokens[at + offset]?.text.toLowerCase() === word,
    );

    if (matches && tokens[at + words.length]?.text === "(") {
      const range = parenthesized(tokens, at + words.length);

      if (range !== undefined) {
        return source.render(tokens.slice(range[0] + 1, range[1]));
      }
    }
  }

  return undefined;
}

function policyOf(
  context: Context,
  policy: Obj,
  tokens: readonly ScanToken[],
  line: number,
): PolicyFact {
  const relation = obj(policy["table"]);
  const table = qualify(context, relation);
  const onAt = tokens.findIndex((token) => token.kind === "ON");
  // Skip the table name: `a` or `a . b`.
  let after = onAt + 2;

  if (tokens[after]?.text === ".") {
    after += 2;
  }

  return {
    name: str(policy["policy_name"]) ?? "",
    table,
    line,
    index: context.index,
    command: str(policy["cmd_name"]) ?? "all",
    permissive: policy["permissive"] !== false,
    roles: roleNames(policy["roles"]),
    using: clauseText(context.source, tokens, ["using"]),
    withCheck: clauseText(context.source, tokens, ["with", "check"]),
    terms: context.source.render(tokens.slice(after)).toLowerCase(),
  };
}

/** The leading plain columns of an index, and whether every key is one. */
function indexColumns(statement: Obj): {
  readonly columns: readonly string[];
  readonly plain: boolean;
} {
  const columns: string[] = [];

  for (const item of list(statement["indexParams"])) {
    const element = bodyOf(item, "IndexElem");
    const name = str(element?.["name"]);

    if (
      element === undefined ||
      name === undefined ||
      name === "" ||
      list(element["opclass"]).length > 0 ||
      list(element["collation"]).length > 0
    ) {
      return { columns, plain: false };
    }

    columns.push(name);
  }

  return { columns, plain: true };
}

function indexOf(
  context: Context,
  statement: Obj,
  tokens: readonly ScanToken[],
  line: number,
): IndexFact {
  const open = tokens.findIndex((token) => token.kind === "ON");
  const keys = parenthesized(tokens, open);

  const keyTokens =
    keys === undefined ? [] : tokens.slice(keys[0] + 1, keys[1]);

  const where = tokens.findIndex(
    (token, at) => token.kind === "WHERE" && at > (keys?.[1] ?? 0),
  );

  return {
    name: nonEmpty(str(statement["idxname"])),
    table: qualify(context, obj(statement["relation"])),
    line,
    index: context.index,
    unique: statement["unique"] === true,
    method: str(statement["accessMethod"]) ?? "btree",
    keys: topLevelParts(keyTokens).map((part) => context.source.render(part)),
    ...indexColumns(statement),
    predicate:
      where === -1 ? undefined : context.source.render(tokens.slice(where + 1)),
    ifNotExists: statement["if_not_exists"] === true,
    text: context.source.render(tokens),
  };
}

function signatureOf(source: Source, types: readonly unknown[]): string {
  return types
    .map((type) => {
      const location = obj(type)["location"];

      return typeof location === "number"
        ? typeText(source, location, new Set(["DEFAULT"]))
        : "";
    })
    .join(", ");
}

function functionOf(
  context: Context,
  statement: Obj,
  line: number,
): FunctionFact {
  const parameters = list(statement["parameters"]).flatMap((item) => {
    const parameter = bodyOf(item, "FunctionParameter");
    const mode = str(parameter?.["mode"]);

    // Table columns of `returns table` are not arguments.
    return parameter === undefined || mode === "FUNC_PARAM_TABLE"
      ? []
      : [bodyOf({ TypeName: parameter["argType"] }, "TypeName")];
  });

  const as = list(statement["options"]).flatMap((item) => {
    const option = bodyOf(item, "DefElem");

    return option?.["defname"] === "as"
      ? strings(bodyOf(option["arg"], "List")?.["items"])
      : [];
  });

  return {
    name: qualifiedNames(context, strings(statement["funcname"])),
    signature: signatureOf(context.source, parameters),
    line,
    index: context.index,
    ifNotExists: false,
    procedure: statement["is_procedure"] === true,
    arity: parameters.length,
    body: as[0],
  };
}

function grantOf(context: Context, grant: Obj): GrantFact {
  return {
    grant: grant["is_grant"] === true,
    privileges: list(grant["privileges"]).flatMap((item) => {
      const name = str(bodyOf(item, "AccessPriv")?.["priv_name"]);

      return name === undefined ? [] : [name];
    }),
    objectType: str(grant["objtype"]) ?? "",
    objects: list(grant["objects"]).flatMap((item) => {
      const relation = bodyOf(item, "RangeVar");

      return relation === undefined ? [] : [qualify(context, relation)];
    }),
    roles: roleNames(grant["grantees"]),
    index: context.index,
  };
}

function viewOf(
  context: Context,
  view: Obj,
  line: number,
  materialized: boolean,
): ViewFact {
  const aliases = strings(view["aliases"]);

  const invoker = list(view["options"]).flatMap((item) => {
    const option = bodyOf(item, "DefElem");

    return option?.["defname"] === "security_invoker"
      ? [str(bodyOf(option["arg"], "String")?.["sval"]) !== "false"]
      : [];
  });

  return {
    name: qualify(context, obj(view["view"])),
    line,
    index: context.index,
    materialized,
    replace: view["replace"] === true,
    columnAliases: aliases.length === 0 ? undefined : aliases,
    securityInvoker: invoker[0],
    columns: aliases.length === 0 ? selectNames(view["query"]) : aliases,
    updatable: !materialized && !blocksWrites(view["query"]),
  };
}

const MARKERS = [
  { kind: "pg-delta", pattern: /^--\s*pg-delta:/i },
  { kind: "rename", pattern: /^--\s*bsb:\s*rename\b/i },
  { kind: "bsb", pattern: /^--\s*@bsb-/i },
] as const;

function markersOf(source: Source): readonly MarkerFact[] {
  return source.comments.flatMap((comment) => {
    const text = comment.text.trimEnd();
    const marker = MARKERS.find((each) => each.pattern.test(text));

    return marker === undefined
      ? []
      : [{ kind: marker.kind, text, line: source.lineAt(comment.start) }];
  });
}

const DO_CREATES =
  /\bcreate\s+(?:or\s+replace\s+)?(?:unique\s+)?(?:table|index|view|function|trigger|policy|type|schema)\b|\bexecute\b/i;

const MODULE_NAME =
  /^-- @(?:bsb-block|bs-module)(?:-data)? ([a-zA-Z0-9-]+)(?:@\d+)?\b/;

function moduleNameOf(source: Source): string | undefined {
  for (const comment of source.comments) {
    const name = MODULE_NAME.exec(comment.text)?.[1];

    if (name !== undefined) {
      return name;
    }
  }

  return undefined;
}

const MODULE_FILE = /^-- @(?:bsb-block|bs-module) /m;

/** Each statement of a parsed file, with where it starts and ends. */
export interface RawStatement {
  readonly stmt?: unknown;
  readonly stmt_location?: number;
  readonly stmt_len?: number;
}

/** The facts of one file, from its parse tree and tokens. */
export function factsFrom(
  source: Source,
  statements: readonly RawStatement[],
): FileFacts {
  const context: Context = { source, schema: "public", index: 0 };
  const tables: TableFact[] = [];
  const alters: AlterFact[] = [];
  const drops: DropFact[] = [];
  const enums: EnumFact[] = [];
  const views: ViewFact[] = [];
  const indexes: IndexFact[] = [];
  const policies: PolicyFact[] = [];
  const triggers: TriggerFact[] = [];
  const functions: FunctionFact[] = [];
  const comments: CommentFact[] = [];
  const grants: GrantFact[] = [];
  const objects: ObjectFact[] = [];
  const doBlocks: number[] = [];
  const doCreates: number[] = [];
  const inserts: number[] = [];
  const declared: DeclaredFact[] = [];
  const calls: CallFact[] = [];
  const audits: AuditFact[] = [];
  const lines: { line: number; kind: string }[] = [];

  for (const [index, raw] of statements.entries()) {
    context.index = index;

    const start = raw.stmt_location ?? 0;

    const end =
      raw.stmt_len === undefined || raw.stmt_len === 0
        ? source.bytes.length
        : start + raw.stmt_len;

    const tokens = source.within(start, end);
    const line = source.lineAt(tokens[0]?.start ?? start);
    const unwrapped = unwrap(raw.stmt);

    if (unwrapped === undefined) {
      continue;
    }

    const [kind, body] = unwrapped;

    lines.push({ line, kind });

    switch (kind) {
      case "CreateStmt": {
        const table = tableOf(context, body, line, false);

        tables.push(table);
        declared.push({
          kind: "table",
          name: table.name,
          line,
          ifNotExists: table.ifNotExists,
        });

        break;
      }

      case "CreateTableAsStmt": {
        const into = obj(obj(body["into"])["rel"]);

        if (body["objtype"] === "OBJECT_MATVIEW") {
          const view = viewOf(
            context,
            { view: into, query: body["query"] },
            line,
            true,
          );

          views.push(view);
          declared.push({
            kind: "view",
            name: view.name,
            line,
            ifNotExists: body["if_not_exists"] === true,
          });

          break;
        }

        const table = tableOf(
          context,
          { relation: into, tableElts: [] },
          line,
          true,
        );

        tables.push(table);
        declared.push({
          kind: "table",
          name: table.name,
          line,
          ifNotExists: body["if_not_exists"] === true,
        });

        break;
      }

      case "AlterTableStmt": {
        alters.push(alterOf(context, body, line));

        break;
      }

      case "DropStmt": {
        const dropped = dropsOf(context, body);

        drops.push(...dropped);

        audits.push(
          ...dropped.flatMap((drop): AuditFact[] =>
            drop.kind === "table"
              ? [{ kind: "drop", target: drop.name, index }]
              : [],
          ),
        );

        break;
      }

      case "CreateEnumStmt": {
        const name = qualifiedNames(context, strings(body["typeName"]));

        enums.push({ name, labels: strings(body["vals"]), line });
        declared.push({ kind: "type", name, line, ifNotExists: false });

        break;
      }

      case "CompositeTypeStmt":
      case "CreateRangeStmt": {
        const typeName = list(
          kind === "CompositeTypeStmt"
            ? [{ RangeVar: body["typevar"] }]
            : body["typeName"],
        );

        const range = bodyOf(typeName[0], "RangeVar");

        declared.push({
          kind: "type",
          name:
            range === undefined
              ? qualifiedNames(context, strings(body["typeName"]))
              : qualify(context, range),
          line,
          ifNotExists: false,
        });

        break;
      }

      case "ViewStmt": {
        const view = viewOf(context, body, line, false);

        views.push(view);
        declared.push({
          kind: "view",
          name: view.name,
          line,
          ifNotExists: false,
        });

        break;
      }

      case "IndexStmt": {
        const created = indexOf(context, body, tokens, line);

        indexes.push(created);

        if (created.name !== undefined) {
          declared.push({
            kind: "index",
            name: `${created.table.slice(0, created.table.indexOf("."))}.${created.name}`,
            line,
            ifNotExists: created.ifNotExists,
          });
        }

        break;
      }

      case "CreatePolicyStmt": {
        const policy = policyOf(context, body, tokens, line);

        policies.push(policy);
        declared.push({
          kind: "policy",
          name: `${policy.table}.${policy.name}`,
          line,
          ifNotExists: false,
        });

        break;
      }

      case "CreateTrigStmt": {
        const events: string[] = [];
        const mask = typeof body["events"] === "number" ? body["events"] : 0;

        events.push(
          ...TRIGGER_EVENTS.flatMap(([bit, name]) =>
            hasBit(mask, bit) ? [name] : [],
          ),
        );

        const trigger: TriggerFact = {
          name: str(body["trigname"]) ?? "",
          table: qualify(context, obj(body["relation"])),
          line,
          index,
          function: qualifiedNames(context, strings(body["funcname"])),
          timing: timingOf(
            typeof body["timing"] === "number" ? body["timing"] : 0,
          ),
          events,
          text: source.render(tokens),
        };

        triggers.push(trigger);

        const audit = auditTrigger(body, trigger.table, index);

        if (audit !== undefined) {
          audits.push(audit);
        }

        declared.push({
          kind: "trigger",
          name: `${trigger.table}.${trigger.name}`,
          line,
          ifNotExists: false,
        });

        break;
      }

      case "CreateFunctionStmt": {
        const created = functionOf(context, body, line);

        functions.push(created);
        declared.push({
          kind: "function",
          name: created.name,
          arity: created.arity,
          line,
          ifNotExists: false,
        });

        break;
      }

      case "SelectStmt": {
        calls.push(...callsOf(body, index));
        audits.push(...auditCalls(body, index));

        break;
      }

      case "RenameStmt": {
        if (body["renameType"] === "OBJECT_TABLE") {
          const relation = obj(body["relation"]);
          const target = qualify(context, relation);

          audits.push({
            kind: "rename",
            target,
            to: `${target.slice(0, target.indexOf("."))}.${str(body["newname"]) ?? ""}`,
            index,
          });
        }

        break;
      }

      case "CommentStmt": {
        const comment = commentOf(
          {
            names: (parts) => qualifiedNames(context, parts),
            signature: (types) => signatureOf(source, types),
          },
          body,
          line,
        );

        if (comment !== undefined) {
          const literal = tokens.findLast((token) =>
            token.kind.endsWith("SCONST"),
          );

          comments.push(
            literal === undefined
              ? comment
              : {
                  ...comment,
                  span: [
                    source.slice(0, literal.start).length,
                    source.slice(0, literal.end).length,
                  ],
                },
          );
        }

        break;
      }

      case "GrantStmt": {
        grants.push(grantOf(context, body));

        break;
      }

      case "DoStmt": {
        doBlocks.push(line);

        const code = list(body["args"]).flatMap((item) => {
          const option = bodyOf(item, "DefElem");

          return option?.["defname"] === "as"
            ? [str(bodyOf(option["arg"], "String")?.["sval"]) ?? ""]
            : [];
        });

        if (DO_CREATES.test(code.join(" "))) {
          doCreates.push(line);
        }

        break;
      }

      case "InsertStmt": {
        inserts.push(line);

        break;
      }

      case "CreateSeqStmt": {
        const fact: ObjectFact = {
          kind: "sequence",
          name: qualify(context, obj(body["sequence"])),
          line,
          ifNotExists: body["if_not_exists"] === true,
        };

        objects.push(fact);
        declared.push({ ...fact, kind: "sequence" });

        break;
      }

      case "CreateSchemaStmt": {
        const fact: ObjectFact = {
          kind: "schema",
          name: str(body["schemaname"]) ?? "",
          line,
          ifNotExists: body["if_not_exists"] === true,
        };

        objects.push(fact);
        declared.push({ ...fact, kind: "schema" });

        break;
      }

      case "CreateExtensionStmt": {
        const schema = list(body["options"]).flatMap((item) => {
          const option = bodyOf(item, "DefElem");

          return option?.["defname"] === "schema"
            ? [str(bodyOf(option["arg"], "String")?.["sval"])]
            : [];
        })[0];

        const fact: ObjectFact = {
          kind: "extension",
          name: str(body["extname"]) ?? "",
          line,
          ifNotExists: body["if_not_exists"] === true,
          ...(schema === undefined ? {} : { schema }),
        };

        objects.push(fact);
        declared.push({ ...fact, kind: "extension" });

        break;
      }

      case "CreateDomainStmt": {
        const name = qualifiedNames(context, strings(body["domainname"]));

        objects.push({ kind: "type", name, line, ifNotExists: false });
        declared.push({ kind: "type", name, line, ifNotExists: false });

        break;
      }

      case "VariableSetStmt": {
        if (body["name"] === "search_path") {
          const first = list(body["args"])
            .map((arg) => str(obj(obj(bodyOf(arg, "A_Const"))["sval"])["sval"]))
            .find((name) => name !== undefined && name !== "$user");

          context.schema = first ?? "public";
        }

        break;
      }

      default: {
        break;
      }
    }
  }

  const markers = markersOf(source);

  const moduleName = moduleNameOf(source);

  return {
    tables,
    alters,
    drops,
    enums,
    views,
    indexes,
    policies,
    triggers,
    functions,
    comments,
    grants,
    objects,
    markers,
    declared,
    calls,
    audits,
    module: source.comments.some((comment) =>
      MODULE_FILE.test(comment.text.startsWith("--") ? comment.text : ""),
    ),
    ...(moduleName === undefined ? {} : { moduleName }),
    doBlocks,
    doCreates,
    inserts,
    statements: lines,
    outsideTransaction: source.comments.some((comment) =>
      /^--\s*pg-delta:\s*transaction\s*=\s*false\b/i.test(comment.text),
    ),
  };
}
