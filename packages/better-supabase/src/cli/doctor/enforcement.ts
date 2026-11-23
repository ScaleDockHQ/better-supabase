import type { Node, ObjectExpression } from "oxc-parser";

import { walk } from "oxc-walker";

import type { FindingInput, Rule, TextFile } from "./rules.ts";

import { lineColumn, parseSource } from "../config-document/parse.ts";

const WRITE_METHODS = new Set(["POST", "PUT", "PATCH", "DELETE"]);

type DefinitionKind = "action" | "route" | "resource action" | "MCP tool";

interface Unset {
  readonly kind: DefinitionKind;
  readonly name: string;
  readonly offset: number;
}

function keyName(node: Node): string | undefined {
  if (node.type === "Identifier") {
    return node.name;
  }

  return node.type === "Literal" && typeof node.value === "string"
    ? node.value
    : undefined;
}

function property(object: ObjectExpression, name: string): Node | undefined {
  for (const entry of object.properties) {
    if (
      entry.type === "Property" &&
      !entry.computed &&
      keyName(entry.key) === name
    ) {
      return entry.value;
    }
  }

  return undefined;
}

function has(object: ObjectExpression, name: string): boolean {
  return property(object, name) !== undefined;
}

function stringValue(node: Node | undefined): string | undefined {
  if (node?.type === "Literal" && typeof node.value === "string") {
    return node.value;
  }

  return node?.type === "TemplateLiteral" && node.expressions.length === 0
    ? (node.quasis[0]?.value.cooked ?? undefined)
    : undefined;
}

/** The name a call's result is bound to: `const name =` or `name:`. */
function boundName(parent: Node | null): string | undefined {
  if (
    parent?.type === "VariableDeclarator" &&
    parent.id.type === "Identifier"
  ) {
    return parent.id.name;
  }

  return parent?.type === "Property" && !parent.computed
    ? keyName(parent.key)
    : undefined;
}

/** `x.name(` with a plain property name. */
function calledMember(node: Node): string | undefined {
  return node.type === "CallExpression" &&
    node.callee.type === "MemberExpression" &&
    !node.callee.computed &&
    node.callee.property.type === "Identifier"
    ? node.callee.property.name
    : undefined;
}

function guarded(object: Node | undefined): object is ObjectExpression {
  return (
    object?.type === "ObjectExpression" &&
    has(object, "permission") &&
    !has(object, "enforcement")
  );
}

function resourceActionWrites(definition: ObjectExpression): boolean {
  const intent = stringValue(property(definition, "intent"));

  if (intent !== undefined) {
    return intent === "write";
  }

  return stringValue(property(definition, "method"))?.toUpperCase() !== "GET";
}

function toolWrites(definition: ObjectExpression): boolean {
  const annotations = property(definition, "annotations");

  const readOnly =
    annotations?.type === "ObjectExpression"
      ? property(annotations, "readOnlyHint")
      : undefined;

  return !(readOnly?.type === "Literal" && readOnly.value === true);
}

/** Write definitions in `file` that check a permission and set no `enforcement`. */
function unsetEnforcement(file: TextFile): readonly Unset[] {
  const found: Unset[] = [];

  walk(parseSource(file.text).program, {
    enter(node, parent) {
      if (node.type === "CallExpression") {
        const member = calledMember(node);
        const [first, second] = node.arguments;

        if (member === "action" && guarded(first)) {
          found.push({
            kind: "action",
            name: boundName(parent) ?? "(unnamed)",
            offset: node.start,
          });
        }

        const method = boundName(parent);

        if (
          member === "route" &&
          guarded(second) &&
          method !== undefined &&
          WRITE_METHODS.has(method)
        ) {
          found.push({ kind: "route", name: method, offset: node.start });
        }

        const definesTool =
          member === "tool" ||
          (node.callee.type === "Identifier" &&
            node.callee.name === "defineTool");

        const tool = definesTool ? first : undefined;

        if (guarded(tool) && toolWrites(tool)) {
          found.push({
            kind: "MCP tool",
            name:
              stringValue(property(tool, "name")) ??
              boundName(parent) ??
              "(unnamed)",
            offset: node.start,
          });
        }

        return;
      }

      if (
        node.type === "Property" &&
        !node.computed &&
        keyName(node.key) === "actions" &&
        node.value.type === "ObjectExpression"
      ) {
        for (const entry of node.value.properties) {
          if (
            entry.type !== "Property" ||
            entry.computed ||
            !guarded(entry.value) ||
            !(has(entry.value, "method") || has(entry.value, "path")) ||
            !resourceActionWrites(entry.value)
          ) {
            continue;
          }

          found.push({
            kind: "resource action",
            name: keyName(entry.key) ?? "(unnamed)",
            offset: entry.start,
          });
        }
      }
    },
  });

  return found;
}

export const ENFORCEMENT_RULES: readonly Rule[] = [
  {
    code: "BS429",
    severity: "info",
    title: "A write definition sets no enforcement",
    description:
      'An action, a route bound to `POST`, `PUT`, `PATCH` or `DELETE`, a resource action that writes, or an MCP tool without `annotations.readOnlyHint: true` that checks a `permission` and sets no `enforcement` reaches the authorizer as `definer`. A provider then reads the authorization version live on each check, because a `security definer` function or the admin client could do the write. Doctor lists each one with its file and line so the choice is visible. Set `enforcement: "rls"` only when every write in the definition runs through the caller\'s `db`, where RLS checks it again; set `"definer"` to record the default.',
    check: (context) => {
      const findings: FindingInput[] = [];

      for (const file of context.sources) {
        for (const unset of unsetEnforcement(file)) {
          findings.push({
            message: `The ${unset.kind} ${unset.name} in ${file.path} writes and sets no enforcement, so its permission check runs as "definer" and reads the authorization version live. Set enforcement: "rls" only when every write in it runs through the caller's db; otherwise set "definer" to record the choice.`,
            target: `${file.path}:${unset.name}`,
            location: {
              file: file.path,
              line: lineColumn(file.text, unset.offset).line,
            },
          });
        }
      }

      return findings;
    },
  },
];
