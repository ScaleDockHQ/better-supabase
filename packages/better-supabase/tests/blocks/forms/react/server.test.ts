import { describe, expect, it } from "vitest";

import { formSchema } from "../../../../src/blocks/forms/index.ts";
import * as client from "../../../../src/blocks/forms/react/index.ts";
import * as server from "../../../../src/blocks/forms/react/server.ts";
import { SIGNUP } from "../fixtures.ts";

describe("forms react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useQuestionnaire", () => {
    expect(() =>
      server.useQuestionnaire({
        form: { definition: SIGNUP, schema: formSchema(SIGNUP) },
        onSubmit: () => {},
      }),
    ).toThrow("useQuestionnaire() runs in Client Components only");
  });
});
