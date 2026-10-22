/**
 * Pins `blocks["webhooks-out"].options.defaultFormat` in an adopted
 * outgoing-webhooks block that maps no `columns.endpoints.format`. Such a block
 * sends every endpoint in `defaultFormat`, whose default moved from the 0.8
 * body (`standard`) to `cloudevents` in 0.9, and which adopt mode requires
 * since 0.11.
 */

import type { CodemodConfigEdit } from "../codemod.ts";
import type { ConfigEdit, Property } from "./config-edit.ts";

import { isRecord } from "../guards.ts";
import {
  configObject,
  mask,
  properties,
  setPathInConfig,
  setPathInJson,
} from "./config-edit.ts";

export type WebhookFormat = "standard" | "cloudevents";

/** The edit, or `undefined` when the config needs none. */
export type FormatPin = ConfigEdit | undefined;

const PATH = ["blocks", "webhooks-out", "options", "defaultFormat"] as const;

function needsPin(block: unknown): boolean {
  if (!isRecord(block) || block["mode"] !== "adopt") {
    return false;
  }

  const options = block["options"];
  const columns = block["columns"];
  const endpoints = isRecord(columns) ? columns["endpoints"] : undefined;

  return (
    !(isRecord(options) && options["defaultFormat"] !== undefined) &&
    !(isRecord(endpoints) && endpoints["format"] !== undefined)
  );
}

function pinJson(source: string, format: WebhookFormat): FormatPin {
  let config: unknown;

  try {
    config = JSON.parse(source);
  } catch {
    return { ok: false, reason: "it isn't valid JSON" };
  }

  const blocks = isRecord(config) ? config["blocks"] : undefined;

  return isRecord(blocks) && needsPin(blocks["webhooks-out"])
    ? setPathInJson(source, PATH, format)
    : undefined;
}

/** The object literal at `prop`'s value, or `undefined` when it isn't one. */
function objectAt(
  source: string,
  code: string,
  prop: Property | undefined,
): readonly Property[] | undefined {
  return prop && code[prop.valueStart] === "{"
    ? properties(source, code, prop.valueStart)
    : undefined;
}

function pinTs(source: string, format: WebhookFormat): FormatPin {
  const code = mask(source);
  const root = configObject(code);

  if (root === undefined) {
    return undefined;
  }

  const find = (props: readonly Property[] | undefined, key: string) =>
    props?.find((prop) => prop.key === key);

  const blocks = objectAt(
    source,
    code,
    find(properties(source, code, root), "blocks"),
  );

  const blockProp = find(blocks, "webhooks-out");

  if (!blockProp) {
    return undefined;
  }

  const block = objectAt(source, code, blockProp);

  if (!block) {
    return {
      ok: false,
      reason: 'its blocks["webhooks-out"] isn\'t a literal object',
    };
  }

  const mode = find(block, "mode");

  const modeText = mode
    ? source.slice(mode.valueStart, mode.valueEnd).trim()
    : undefined;

  if (modeText !== '"adopt"' && modeText !== "'adopt'") {
    return undefined;
  }

  const options = find(block, "options");
  const columns = find(block, "columns");

  if (
    (options && !objectAt(source, code, options)) ||
    (columns && !objectAt(source, code, columns))
  ) {
    return {
      ok: false,
      reason:
        'its blocks["webhooks-out"] options or columns aren\'t literal objects',
    };
  }

  const endpoints = find(objectAt(source, code, columns), "endpoints");

  if (endpoints && !objectAt(source, code, endpoints)) {
    return {
      ok: false,
      reason:
        'its blocks["webhooks-out"].columns.endpoints isn\'t a literal object',
    };
  }

  if (
    find(objectAt(source, code, options), "defaultFormat") ||
    find(objectAt(source, code, endpoints), "format")
  ) {
    return undefined;
  }

  return setPathInConfig(source, PATH, format);
}

/**
 * Pins `defaultFormat` to `format` where an adopted block leaves it to the
 * default.
 */
export function pinWebhookFormat(
  source: string,
  json: boolean,
  format: WebhookFormat,
): FormatPin {
  return json ? pinJson(source, format) : pinTs(source, format);
}

/**
 * `edit` with `defaultFormat` pinned to `format` where an adopted webhooks-out
 * block needs it.
 */
export function withWebhookFormat(
  edit: CodemodConfigEdit,
  json: boolean,
  format: WebhookFormat,
): CodemodConfigEdit {
  if (!edit.ok) {
    return edit;
  }

  const earlier = "review" in edit ? edit.review : [];
  const pin = pinWebhookFormat(edit.text, json, format);

  if (pin === undefined) {
    return { ok: true, text: edit.text, review: earlier };
  }

  if (!pin.ok) {
    return {
      ok: true,
      text: edit.text,
      review: [
        ...earlier,
        {
          line: 1,
          message: `blocks["webhooks-out"] is adopted and maps no columns.endpoints.format, but defaultFormat wasn't pinned: ${pin.reason}. Set options.defaultFormat to "${format}" to keep the body endpoints get now`,
        },
      ],
    };
  }

  const line =
    pin.text.split("\n").findIndex((text) => text.includes("defaultFormat")) +
    1;

  return {
    ok: true,
    text: pin.text,
    review: [
      ...earlier,
      {
        line: Math.max(line, 1),
        message: `blocks["webhooks-out"] is adopted and maps no columns.endpoints.format, so the codemod set options.defaultFormat to "${format}", the body its endpoints get now. Change it if your receivers expect the other format`,
      },
    ],
  };
}
