import { createLoader, parseAsString } from "nuqs/server";

/** A stored chat's URL state: the leaf message of the branch it shows. */
export const loadChatBranch = createLoader({ leaf: parseAsString });
