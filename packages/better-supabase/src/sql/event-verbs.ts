import { NOTHING } from "./shared.ts";

/**
 * `render("created")` when the boolean expression `inserted` holds and
 * `render("updated")` otherwise, for a writer that both inserts and updates.
 * Renders nothing when neither branch does, for example with events off.
 */
export function createdOrUpdated(
  inserted: string,
  render: (verb: "created" | "updated") => string,
): string {
  const created = render("created");
  const updated = render("updated");

  if (created.trim() === "" && updated.trim() === "") {
    return "";
  }

  return `if ${inserted} then
    ${created.trim() === "" ? NOTHING : created.trim()}
  else
    ${updated.trim() === "" ? NOTHING : updated.trim()}
  end if;`;
}
