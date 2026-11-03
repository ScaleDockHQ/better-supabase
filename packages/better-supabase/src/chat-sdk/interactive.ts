import { isRecord, optionalText } from "../core/block-helpers.ts";

/**
 * A button or list choice a contact picked on a channel, as an inbound action:
 * the same fact as a Chat SDK `ActionEvent`, read from the raw webhook body.
 */
export interface ChatInteractiveAction {
  /**
   * Where the reply came from: a quick reply button, a list row or a template
   * button.
   */
  readonly kind: "button_reply" | "list_reply" | "quick_reply";
  /** The button id, the list row id, or a template button's payload. */
  readonly actionId: string;
  /** The text the contact saw and tapped. */
  readonly title?: string;
  /** A list row's description. */
  readonly description?: string;
  /** The contact's platform id (for WhatsApp, their `wa_id`). */
  readonly from: string;
  /** The contact's profile name, when the payload carries one. */
  readonly name?: string;
  /** The platform's id for the reply message. */
  readonly messageId: string;
  /** The id of the message the button was on, when the payload says. */
  readonly contextMessageId?: string;
}

/** What an interactive parser found in one stored webhook body. */
export interface ParsedInteractive {
  readonly actions: readonly ChatInteractiveAction[];
  /** True when the body holds nothing but interactive replies. */
  readonly only: boolean;
}

/**
 * Reads interactive replies from a stored webhook event; `null` for other
 * bodies.
 */
export type InteractiveParser = (event: {
  readonly body: string;
}) => ParsedInteractive | null;

function json(body: string): unknown {
  try {
    return JSON.parse(body);
  } catch {
    return undefined;
  }
}

const list = (value: unknown): readonly unknown[] =>
  Array.isArray(value) ? value : [];

/** What the contact picked in one WhatsApp message, or `null`. */
function replyOf(
  message: Record<string, unknown>,
): Pick<
  ChatInteractiveAction,
  "kind" | "actionId" | "title" | "description"
> | null {
  const interactive = message["interactive"];

  if (message["type"] === "interactive" && isRecord(interactive)) {
    const button = interactive["button_reply"];
    const row = interactive["list_reply"];

    if (isRecord(button)) {
      const id = optionalText(button["id"]);
      const title = optionalText(button["title"]);

      return id === undefined
        ? null
        : {
            kind: "button_reply",
            actionId: id,
            ...(title === undefined ? {} : { title }),
          };
    }

    if (isRecord(row)) {
      const id = optionalText(row["id"]);
      const title = optionalText(row["title"]);
      const description = optionalText(row["description"]);

      return id === undefined
        ? null
        : {
            kind: "list_reply",
            actionId: id,
            ...(title === undefined ? {} : { title }),
            ...(description === undefined ? {} : { description }),
          };
    }

    return null;
  }

  const quick = message["button"];

  if (message["type"] === "button" && isRecord(quick)) {
    const text = optionalText(quick["text"]);
    const id = optionalText(quick["payload"]) ?? text;

    return id === undefined
      ? null
      : {
          kind: "quick_reply",
          actionId: id,
          ...(text === undefined ? {} : { title: text }),
        };
  }

  return null;
}

/**
 * The button and list replies in a WhatsApp Cloud API webhook body (a string or
 * its parsed JSON): `interactive.button_reply`, `interactive.list_reply` and a
 * template's quick reply (`type: "button"`). Other messages and status
 * callbacks are skipped.
 */
export function whatsappInteractiveOf(
  payload: unknown,
): readonly ChatInteractiveAction[] {
  return readWhatsapp(payload)?.actions ?? [];
}

function readWhatsapp(payload: unknown): ParsedInteractive | null {
  const body = typeof payload === "string" ? json(payload) : payload;

  if (!isRecord(body) || body["object"] !== "whatsapp_business_account") {
    return null;
  }

  const actions: ChatInteractiveAction[] = [];
  let messages = 0;

  for (const entry of list(body["entry"])) {
    for (const change of list(isRecord(entry) ? entry["changes"] : undefined)) {
      const value = isRecord(change) ? change["value"] : undefined;

      if (!isRecord(value)) {
        continue;
      }

      const names = new Map<string, string>();

      for (const contact of list(value["contacts"])) {
        if (!isRecord(contact)) {
          continue;
        }

        const id = optionalText(contact["wa_id"]);
        const profile = contact["profile"];

        const name = isRecord(profile)
          ? optionalText(profile["name"])
          : undefined;

        if (id !== undefined && name !== undefined) {
          names.set(id, name);
        }
      }

      for (const item of list(value["messages"])) {
        if (!isRecord(item)) {
          continue;
        }

        messages += 1;

        const reply = replyOf(item);
        const from = optionalText(item["from"]);
        const messageId = optionalText(item["id"]);

        if (reply === null || from === undefined || messageId === undefined) {
          continue;
        }

        const context = item["context"];

        const contextMessageId = isRecord(context)
          ? optionalText(context["id"])
          : undefined;

        const name = names.get(from);

        actions.push({
          ...reply,
          from,
          messageId,
          ...(name === undefined ? {} : { name }),
          ...(contextMessageId === undefined ? {} : { contextMessageId }),
        });
      }
    }
  }

  return { actions, only: actions.length > 0 && actions.length === messages };
}

/** `whatsappInteractiveOf` as an `InteractiveParser`. */
export const whatsappInteractive: InteractiveParser = ({ body }) =>
  readWhatsapp(body);

/** The parsers `inboundHandler` uses by default, keyed by adapter name. */
export const INTERACTIVE_PARSERS: Readonly<Record<string, InteractiveParser>> =
  { whatsapp: whatsappInteractive };
