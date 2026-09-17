// node-gyp-build ships no type declarations. Only the loader entry point is
// used here; the addon's shape is described at the call site.
declare module "node-gyp-build" {
  function load(dir: string): any;
  export = load;
}
