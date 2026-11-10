import { MODULES, registerOverAppModules } from "./over-app-modules-suite.ts";

const parts = 5;
const size = Math.ceil(MODULES.length / parts);
const part = 2;

registerOverAppModules(MODULES.slice(part * size, (part + 1) * size));
