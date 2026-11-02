/** The kinds of personal data `scanPii` finds. */
export const PII_KINDS = ["card", "iban", "ssn", "email", "phone"] as const;

export type PiiKind = (typeof PII_KINDS)[number];

/** One prompt-injection pattern, named for the reason a decision records. */
export interface InjectionRule {
  readonly id: string;
  readonly pattern: RegExp;
}

/**
 * Heuristics for OWASP LLM01 (prompt injection): instructions that override the
 * system prompt, role and delimiter forgery, prompt extraction and markdown
 * image exfiltration. They flag likely attacks and are no proof of safety, so
 * keep them next to least-privilege tools and output handling.
 */
export const INJECTION_RULES: readonly InjectionRule[] = [
  {
    id: "ignore_instructions",
    pattern:
      /\b(?:ignore|disregard|forget|override|bypass)\b[^.\n]{0,40}\b(?:previous|prior|above|earlier|all|any|your|the)\b[^.\n]{0,30}\b(?:instructions?|rules?|prompts?|guidelines?|directives?)\b/i,
  },
  {
    id: "reveal_prompt",
    pattern:
      /\b(?:reveal|show|print|repeat|output|leak|display|tell me)\b[^.\n]{0,40}\b(?:system|hidden|initial|original|developer)\s+(?:prompt|instructions?|message)\b/i,
  },
  {
    id: "persona_override",
    pattern:
      /\b(?:you are now|from now on you (?:are|will)|pretend (?:to be|you are)|act as if you (?:have|had) no)\b|\b(?:DAN|developer mode|jailbreak(?:ed)?)\b/i,
  },
  {
    id: "role_forgery",
    pattern:
      /^\s*(?:system|assistant|developer)\s*:|<\|(?:im_start|im_end|system|endoftext)\|>|\[\/?INST\]|<<\/?SYS>>|<\/?(?:system|instructions?)>/im,
  },
  {
    id: "new_instructions",
    pattern:
      /\b(?:new|updated|real|actual)\s+(?:instructions?|task|rules?)\s*[:-]/i,
  },
  {
    id: "encoded_payload",
    pattern:
      /\b(?:base64|rot13|hex)\b[^.\n]{0,30}\b(?:decode|decoded|execute|follow|run)\b|\b(?:decode|execute|follow)\b[^.\n]{0,30}\b(?:base64|rot13)\b/i,
  },
  {
    id: "markdown_exfiltration",
    pattern: /!\[[^\]]*\]\(https?:\/\/[^)\s]*[?&][^)\s]*=[^)\s]*\)/i,
  },
];

/** The ids of the injection rules `text` matches. */
export function detectInjection(
  text: string,
  rules: readonly InjectionRule[] = INJECTION_RULES,
): string[] {
  return rules.filter((rule) => rule.pattern.test(text)).map((rule) => rule.id);
}

function luhn(digits: string): boolean {
  let sum = 0;
  let double = false;

  for (let index = digits.length - 1; index >= 0; index -= 1) {
    let digit = Number(digits[index]);

    if (double) {
      digit *= 2;

      if (digit > 9) {
        digit -= 9;
      }
    }

    sum += digit;
    double = !double;
  }

  return sum % 10 === 0;
}

function ibanValid(value: string): boolean {
  const compact = value.replaceAll(/\s/g, "").toUpperCase();

  if (compact.length < 15 || compact.length > 34) {
    return false;
  }

  const rearranged = compact.slice(4) + compact.slice(0, 4);
  let remainder = 0;

  for (const char of rearranged) {
    const code = char.codePointAt(0) ?? 0;
    const chunk = code >= 65 && code <= 90 ? String(code - 55) : char;

    for (const digit of chunk) {
      remainder = (remainder * 10 + Number(digit)) % 97;
    }
  }

  return remainder === 1;
}

type Finder = (match: string) => boolean;

const PII_PATTERNS: Readonly<
  Record<PiiKind, { readonly pattern: RegExp; readonly valid: Finder }>
> = {
  card: {
    pattern: /\b(?:\d[ -]?){13,19}\b/g,
    valid: (match) => {
      const digits = match.replaceAll(/\D/g, "");

      return digits.length >= 13 && digits.length <= 19 && luhn(digits);
    },
  },
  iban: {
    pattern: /\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,4})?\b/g,
    valid: ibanValid,
  },
  ssn: {
    pattern: /\b\d{3}-\d{2}-\d{4}\b/g,
    valid: (match) => !match.startsWith("000") && !match.startsWith("666"),
  },
  email: {
    pattern:
      /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b/g,
    valid: () => true,
  },
  phone: {
    pattern: /(?<![\w.])\+?\d[\d ()./-]{7,17}\d\b/g,
    valid: (match) => {
      const digits = match.replaceAll(/\D/g, "");

      return digits.length >= 9 && digits.length <= 15;
    },
  },
};

/** What `scanPii` found and the text with each match replaced. */
export interface PiiScan {
  /** The text with `[REDACTED:<kind>]` in place of every match. */
  readonly redacted: string;
  /** The number of matches per kind that had at least one. */
  readonly found: Readonly<Partial<Record<PiiKind, number>>>;
}

/**
 * Finds payment card numbers (Luhn checked), IBANs (mod 97 checked), US social
 * security numbers, email addresses and phone numbers. Kinds run in that order
 * and later ones skip text an earlier one already replaced.
 */
export function scanPii(
  text: string,
  kinds: readonly PiiKind[] = PII_KINDS,
): PiiScan {
  const found: Partial<Record<PiiKind, number>> = {};
  let redacted = text;

  for (const kind of PII_KINDS) {
    if (!kinds.includes(kind)) {
      continue;
    }

    const { pattern, valid } = PII_PATTERNS[kind];
    let count = 0;

    redacted = redacted.replaceAll(pattern, (match) => {
      if (!valid(match)) {
        return match;
      }

      count += 1;

      return `[REDACTED:${kind}]`;
    });

    if (count > 0) {
      found[kind] = count;
    }
  }

  return { redacted, found };
}

/** A deny-listed topic: a name for the log and the terms that signal it. */
export interface DenyTopic {
  readonly topic: string;
  readonly terms: readonly string[];
}

/** The topics whose terms appear in `text`, ignoring case. */
export function matchTopics(
  text: string,
  topics: readonly (DenyTopic | string)[],
): string[] {
  const lower = text.toLowerCase();

  return topics.flatMap((entry) => {
    const topic = typeof entry === "string" ? entry : entry.topic;
    const terms = typeof entry === "string" ? [entry] : entry.terms;

    return terms.some(
      (term) => term !== "" && lower.includes(term.toLowerCase()),
    )
      ? [topic]
      : [];
  });
}
