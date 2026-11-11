import { getVisibleNavIds } from "../visible-nav";
import { SideNav } from "./side-nav";

// skeleton: renders from props and translations, so nothing of its own suspends
/**
 * Render inside `<Suspense>`: picks the entries the session's permissions and
 * the organization's flags allow, then hands plain ids to the client menu.
 */
export async function AppNav() {
  return <SideNav visible={await getVisibleNavIds()} />;
}
