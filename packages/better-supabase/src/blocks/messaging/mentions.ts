import type { SubjectRef } from "../../schema/types.ts";

/**
 * Mention markup, the same `parse_mentions` reads in SQL: `@[Ada](user:<user
 * id>)` or `@[Ada](<user id>)` mentions a user, `@[Acme
 * deal](subject:<type>/<id>)` a record, and `@channel` or `@here` the
 * conversation's members.
 */
const UUID =
  "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}";

const NAME = String.raw`\[([^\]\n]{1,100})\]`;
const USER = String.raw`\((?:[uU][sS][eE][rR]:)?(${UUID})\)`;
const TYPE = "[a-z][a-z0-9_]{0,62}";
const RECORD = String.raw`\(subject:(${TYPE})/([^)\s]{1,200})\)`;
const SCOPE = String.raw`(^|[^\w@])@(channel|here)\b`;

const TOKEN = new RegExp(
  String.raw`@${NAME}(?:${USER}|${RECORD})|${SCOPE}`,
  "g",
);

const SUBJECT_TYPE = new RegExp(`^${TYPE}$`);
const SUBJECT_ID = /^[^)\s]{1,200}$/;

/** The longest name a mention keeps. */
const MAX_NAME = 100;

export type MentionScope = "channel" | "here";

export interface ParsedMentions {
  /** Mentioned user ids, lowercase, in order and without repeats. */
  readonly users: readonly string[];
  /** Mentioned records, in order and without repeats. */
  readonly records: readonly SubjectRef[];
  /** `channel` wins over `here` when the body has both, as in SQL. */
  readonly scope: MentionScope | undefined;
}

/** One piece of a body, for rendering mentions as chips. */
export type MentionSegment =
  | { readonly kind: "text"; readonly text: string }
  | { readonly kind: "user"; readonly name: string; readonly userId: string }
  | {
      readonly kind: "record";
      readonly name: string;
      readonly subject: SubjectRef;
    }
  | { readonly kind: "scope"; readonly scope: MentionScope };

/**
 * Splits a body into text and mentions, in order. Adjacent text stays one
 * segment.
 *
 * ```tsx
 * mentionSegments(message.body).map((part) =>
 *   part.kind === "record" ? <RecordChip subject={part.subject} /> : ...
 * );
 * ```
 */
export function mentionSegments(body: string): readonly MentionSegment[] {
  const segments: MentionSegment[] = [];
  let text = "";
  let last = 0;

  const flush = (): void => {
    if (text !== "") {
      segments.push({ kind: "text", text });
      text = "";
    }
  };

  for (const match of body.matchAll(TOKEN)) {
    const [whole, name, userId, type, id, lead, scope] = match;
    text += body.slice(last, match.index);
    last = match.index + whole.length;

    if (scope !== undefined) {
      text += String(lead);
      flush();
      segments.push({
        kind: "scope",
        scope: scope === "here" ? "here" : "channel",
      });
      continue;
    }

    flush();
    segments.push(
      userId === undefined
        ? {
            kind: "record",
            name: String(name),
            subject: { type: String(type), id: String(id) },
          }
        : { kind: "user", name: String(name), userId: userId.toLowerCase() },
    );
  }

  text += body.slice(last);
  flush();

  return segments;
}

/** The users, records and scope a body mentions. */
export function parseMentions(body: string): ParsedMentions {
  const users = new Set<string>();
  const records = new Map<string, SubjectRef>();
  let channel = false;
  let here = false;

  for (const segment of mentionSegments(body)) {
    switch (segment.kind) {
      case "user": {
        users.add(segment.userId);
        break;
      }

      case "record": {
        records.set(
          `${segment.subject.type}/${segment.subject.id}`,
          segment.subject,
        );
        break;
      }

      case "scope": {
        channel ||= segment.scope === "channel";
        here ||= segment.scope === "here";
        break;
      }

      case "text": {
        break;
      }

      default: {
        const never: never = segment;
        throw new TypeError(`unknown mention segment ${String(never)}`);
      }
    }
  }

  return {
    users: [...users],
    records: [...records.values()],
    scope: channel ? "channel" : here ? "here" : undefined,
  };
}

/** A name a mention can hold: one line, no `]`, at most 100 characters. */
function mentionName(name: string, fallback: string): string {
  const clean = name.replaceAll(/[\]\n\r]/g, " ").trim();

  return (clean === "" ? fallback : clean).slice(0, MAX_NAME);
}

/** `@[Name](user:<id>)`: the markup that mentions a user. */
export function userMention(name: string, userId: string): string {
  return `@[${mentionName(name, "user")}](user:${userId})`;
}

/** `@[Name](subject:<type>/<id>)`: the markup that mentions a record. */
export function recordMention(name: string, subject: SubjectRef): string {
  if (!SUBJECT_TYPE.test(subject.type) || !SUBJECT_ID.test(subject.id)) {
    throw new TypeError(
      "better-supabase: a record mention needs a lowercase subject type and an id of at most 200 characters without spaces or )",
    );
  }

  return `@[${mentionName(name, subject.type)}](subject:${subject.type}/${subject.id})`;
}
