/** A box as fractions of the page or frame, measured from its top-left corner. */
export interface AnchorRegion {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

/** Where on a file a message points: a page, a region, a moment or a span. */
export interface FileAnchorAt {
  /** The page, from 1. */
  readonly page?: number;
  /** A box on the page or the video frame, inside 0 to 1. */
  readonly region?: AnchorRegion;
  /** Seconds from the start of an audio or video file. */
  readonly start?: number;
  /** Seconds, after `start`: the end of a span. */
  readonly end?: number;
}

/**
 * A message's anchor on an attachment of its record or conversation.
 * `send_message` checks its shape and that the file is on the same record.
 */
export interface FileAnchor extends FileAnchorAt {
  readonly kind: "file";
  readonly attachmentId: string;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/iu;

const isNumber = (value: unknown): value is number =>
  typeof value === "number" && Number.isFinite(value);

const isRecord = (value: unknown): value is Readonly<Record<string, unknown>> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

function isRegion(value: unknown): value is AnchorRegion {
  if (!isRecord(value)) {
    return false;
  }

  const { x, y, width, height } = value;

  return (
    isNumber(x) &&
    isNumber(y) &&
    isNumber(width) &&
    isNumber(height) &&
    x >= 0 &&
    y >= 0 &&
    width > 0 &&
    height > 0 &&
    x + width <= 1 &&
    y + height <= 1
  );
}

/** Whether `value` is a file anchor `send_message` accepts. */
export function isFileAnchor(value: unknown): value is FileAnchor {
  if (!isRecord(value) || value["kind"] !== "file") {
    return false;
  }

  const { attachmentId, page, region, start, end } = value;

  return (
    typeof attachmentId === "string" &&
    UUID.test(attachmentId) &&
    (page === undefined ||
      (isNumber(page) && Number.isInteger(page) && page >= 1)) &&
    (region === undefined || isRegion(region)) &&
    (start === undefined || (isNumber(start) && start >= 0)) &&
    (end === undefined || (isNumber(start) && isNumber(end) && end > start))
  );
}

/**
 * An anchor on an attachment, for `anchor` on a new message or comment. Throws
 * a `TypeError` when the page, region or span is out of range.
 */
export function fileAnchor(
  attachmentId: string,
  at: FileAnchorAt = {},
): FileAnchor {
  const anchor: FileAnchor = { kind: "file", attachmentId, ...at };

  if (!isFileAnchor(anchor)) {
    throw new TypeError(
      "A file anchor needs an attachment id, a page from 1, a region inside 0 to 1 and a time span from 0",
    );
  }

  return anchor;
}
