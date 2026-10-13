import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
const require = process.env.CAPTUREFOX_TEST_DEPS
  ? createRequire(resolve(process.env.CAPTUREFOX_TEST_DEPS, 'package.json'))
  : createRequire(import.meta.url);
export const testDependency = name => import(pathToFileURL(require.resolve(name)).href);
