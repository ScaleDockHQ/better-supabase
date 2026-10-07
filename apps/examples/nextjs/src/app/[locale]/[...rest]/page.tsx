import { notFound } from "next/navigation";

/** Unknown paths under a locale render `[locale]/not-found.tsx`, translated. */
export default function CatchAll() {
  notFound();
}
