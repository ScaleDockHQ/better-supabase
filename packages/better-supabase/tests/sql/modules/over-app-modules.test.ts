import {
  MODULES,
  registerNeighborCases,
  registerOverAppModules,
} from "./over-app-modules-suite.ts";

const parts = 5;
const size = Math.ceil(MODULES.length / parts);

registerOverAppModules(MODULES.slice(0, size));

registerNeighborCases();
