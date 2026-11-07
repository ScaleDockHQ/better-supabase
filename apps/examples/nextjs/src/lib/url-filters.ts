import { debounce, parseAsString } from "nuqs";

/**
 * `?q=` for a list's search box. The input follows the keystrokes at once and
 * the URL catches up after a pause, so a shared link carries the filter without
 * a history entry per letter.
 */
export const searchParam = parseAsString
  .withDefault("")
  .withOptions({ clearOnDefault: true, limitUrlUpdates: debounce(250) });
