import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import { App } from "./App";
import { Providers } from "./providers";

createRoot(document.querySelector("#root")!).render(
  <StrictMode>
    <Providers>
      <App />
    </Providers>
  </StrictMode>,
);
