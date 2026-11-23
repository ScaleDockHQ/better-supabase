import type { Obj } from "./ast.ts";
import type { CallFact } from "./facts.ts";

import { bodyOf, list, obj, str, strings } from "./ast.ts";

/** Whether `mask` has the bit `bit`, without bitwise operators. */
export const hasBit = (mask: number, bit: number): boolean =>
  Math.floor(mask / bit) % 2 === 1;

export const TRIGGER_EVENTS = [
  [4, "insert"],
  [8, "delete"],
  [16, "update"],
  [32, "truncate"],
] as const;

export function timingOf(mask: number): "before" | "after" | "instead of" {
  if (hasBit(mask, 64)) {
    return "instead of";
  }

  return hasBit(mask, 2) ? "before" : "after";
}

/** A top-level `select f('a', 'b')`: its function calls with string arguments. */
export function callsOf(select: Obj, index: number): readonly CallFact[] {
  return list(select["targetList"]).flatMap((item) => {
    const call = bodyOf(bodyOf(item, "ResTarget")?.["val"], "FuncCall");

    if (call === undefined) {
      return [];
    }

    return [
      {
        name: strings(call["funcname"]).join("."),
        strings: list(call["args"]).flatMap((arg) => {
          const text = str(obj(bodyOf(arg, "A_Const")?.["sval"])["sval"]);

          return text === undefined ? [] : [text];
        }),
        index,
      },
    ];
  });
}
