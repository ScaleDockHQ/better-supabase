import { NAMES, registerGoldenSnapshots } from "./render-golden-suite.ts";

const size = Math.ceil(NAMES.length / 2);

registerGoldenSnapshots(NAMES.slice(size));
