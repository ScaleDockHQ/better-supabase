import type { ESTree, Visitor } from "@oxlint/plugins";

/** Every node that carries a parameter list and an optional return type. */
export type Signature =
  | ESTree.Function
  | ESTree.ArrowFunctionExpression
  | ESTree.TSMethodSignature
  | ESTree.TSCallSignatureDeclaration
  | ESTree.TSConstructSignatureDeclaration
  | ESTree.TSFunctionType
  | ESTree.TSConstructorType;

/** A visitor that calls `check` on every function, method and signature. */
export function signatureVisitor(check: (node: Signature) => void): Visitor {
  return {
    FunctionDeclaration: check,
    FunctionExpression: check,
    ArrowFunctionExpression: check,
    TSDeclareFunction: check,
    TSEmptyBodyFunctionExpression: check,
    TSMethodSignature: check,
    TSCallSignatureDeclaration: check,
    TSConstructSignatureDeclaration: check,
    TSFunctionType: check,
    TSConstructorType: check,
  };
}
