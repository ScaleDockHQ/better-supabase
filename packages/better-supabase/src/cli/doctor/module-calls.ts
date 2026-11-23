import type { Node } from "oxc-parser";

import { isCallOf, isMethodCall } from "./tree.ts";

/** `audit.list(` and `audit.listAll(`. */
export const isAuditListCall = (node: Node): boolean =>
  node.type === "CallExpression" &&
  node.callee.type === "MemberExpression" &&
  !node.callee.computed &&
  node.callee.object.type === "Identifier" &&
  node.callee.object.name === "audit" &&
  node.callee.property.type === "Identifier" &&
  (node.callee.property.name === "list" ||
    node.callee.property.name === "listAll");

/** `deleteAccount`, `x.admin(` or `supabaseAdmin`. */
export const isAdminUse = (node: Node): boolean =>
  (node.type === "Identifier" &&
    (node.name === "deleteAccount" || node.name.endsWith("supabaseAdmin"))) ||
  isMethodCall(node, "admin");

/** `requireAal("aal2"`. */
export const isRequireAal2 = (node: Node): boolean =>
  isCallOf(node, "requireAal") &&
  node.type === "CallExpression" &&
  node.arguments[0]?.type === "Literal" &&
  node.arguments[0].value === "aal2";
