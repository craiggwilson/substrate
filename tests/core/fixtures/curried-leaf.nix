# A curried module for the importApply round-trip test. The outer arguments
# are applied by lib.modules.importApply at the leaf site; the inner function
# is a plain module that must evaluate without any specialArgs.
{ inputs, ... }: { lib, ... }: {
  options.test.curriedValue = lib.mkOption {
    description = "Value carried through the curry, proving the outer arguments were applied.";
    type = lib.types.str;
    default = "";
  };
  config.test.curriedValue = inputs.marker;
}
