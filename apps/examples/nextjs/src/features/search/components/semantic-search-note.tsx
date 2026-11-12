import { useExtracted } from "next-intl";

import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";

// skeleton: renders from translations only, so nothing of its own suspends
/**
 * Why there is no semantic tab yet: the search block ranks by text, and a query
 * vector needs an embedding model the example does not configure.
 */
export function SemanticSearchNote() {
  const t = useExtracted("search");

  return (
    <Alert>
      <AlertTitle>{t("Semantic search")}</AlertTitle>
      <AlertDescription>
        {t(
          "Matching by meaning needs an embedding model for the query. Set AI_GATEWAY_API_KEY to turn it on; text search covers every record today.",
        )}
      </AlertDescription>
    </Alert>
  );
}
