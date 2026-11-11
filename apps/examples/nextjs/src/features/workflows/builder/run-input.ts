import * as v from "valibot";

const Input = v.record(v.string(), v.unknown());

/**
 * The input of a run from the editor's text field: a JSON object is the input
 * as it is (`{"items": ["a"]}` gives `input.items`), anything else is the text
 * of `input.text`.
 */
export function runInput(text: string) {
  const trimmed = text.trim();

  if (trimmed.startsWith("{")) {
    try {
      const parsed = v.safeParse(Input, JSON.parse(trimmed));

      if (parsed.success) {
        return parsed.output;
      }
    } catch {
      // Not JSON: it is text.
    }
  }

  return { text };
}

const Stubs = v.record(v.string(), v.unknown());

/**
 * The test stubs from the run panel: empty text means none, a JSON object maps
 * a node id to the output the node returns, and anything else is refused.
 */
export function parseStubs(text: string) {
  if (text.trim() === "") {
    return { ok: true, stubs: {} } as const;
  }

  try {
    const parsed = v.safeParse(Stubs, JSON.parse(text));

    return parsed.success
      ? ({ ok: true, stubs: parsed.output } as const)
      : ({ ok: false } as const);
  } catch {
    return { ok: false } as const;
  }
}
