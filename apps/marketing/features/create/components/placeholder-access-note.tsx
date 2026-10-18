import type { ReactElement } from "react";

import { InfoIcon } from "lucide-react";

import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";

/**
 * Shown next to the schema and the migrations for `access: "provider"`,
 * which render with the stand-in provider from `lib/preview-provider`.
 */
export function PlaceholderAccessNote(): ReactElement {
  return (
    <Alert variant="info">
      <InfoIcon aria-hidden="true" />
      <AlertTitle>Placeholder access functions</AlertTitle>
      <AlertDescription>
        <p>
          The access functions come from your authorization provider. This
          preview calls placeholder{" "}
          <code className="font-mono">provider.*</code> functions in their
          place.
        </p>
      </AlertDescription>
    </Alert>
  );
}
