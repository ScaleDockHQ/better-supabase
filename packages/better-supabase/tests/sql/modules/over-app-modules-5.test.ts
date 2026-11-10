import { MODULES, registerOverAppModules } from "./over-app-modules-suite.ts";

const parts = 5;
const size = Math.ceil(MODULES.length / parts);
const part = 4;

registerOverAppModules(MODULES.slice(part * size));
