# Top-level `secretspec` namespace, shared by the NixOS and Home Manager
# classes and named after the tool it configures (like `sops` or `age`).
# Included via imports from each class module; the substrate secrets extension
# pushes those modules into the appropriate configurations, so any class module
# can declare secrets without referencing the extension itself.
#
# Import parameters tune the per-class defaults of entries.<name>.file (local
# materialization policy): filesDir is the default directory for materialized
# files and owner/group are the default ownership; both belong to the class
# module that imports this, so options stay class-neutral here.
{
  lib,
  filesDir ? "/var/lib/secretspec/files",
  owner ? "root",
  group ? "root",
  ...
}:
{
  options.secretspec = {
    entries = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              description = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Human-readable purpose of the secret, shown by secretspec tooling.";
              };

              required = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether resolution fails when the secret is missing.";
              };

              default = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Committed fallback value (never use for actual secrets).";
              };

              prompt = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Prompt for the value at resolution time when missing.";
              };

              asPath = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Materialize to a temporary file at resolution and expose its path.";
              };

              # Local placement policy: resolves the entry at runtime and writes
              # its value to path. null = the entry is consumed as an
              # environment variable or through the secretspec CLI only.
              file = lib.mkOption {
                type = lib.types.nullOr (
                  lib.types.submodule {
                    options = {
                      path = lib.mkOption {
                        type = lib.types.str;
                        default = "${filesDir}/${name}";
                        description = "Runtime file the entry's value is written to, resolved at materialization time; never a Nix store path.";
                      };

                      fileOwner = lib.mkOption {
                        type = lib.types.str;
                        default = owner;
                        description = "User who owns the materialized file.";
                      };

                      fileGroup = lib.mkOption {
                        type = lib.types.str;
                        default = group;
                        description = "Group who owns the materialized file.";
                      };

                      mode = lib.mkOption {
                        type = lib.types.str;
                        default = "0600";
                        description = "Permissions of the materialized file, octal.";
                      };
                    };
                  }
                );
                default = null;
                description = ''
                  Materialization policy: resolves the entry at runtime and writes
                  its value to path with the given ownership and mode. Mutually
                  exclusive with asPath.
                '';
              };

              providers = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                example = [
                  "team"
                  "keyring"
                ];
                description = ''
                  Ordered fallback chain of provider aliases (from secretspec.providers)
                  or full provider URIs. Empty means the profile defaults.
                '';
              };

              ref = lib.mkOption {
                type = lib.types.nullOr (
                  lib.types.submodule {
                    options = {
                      vault = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = "Override the provider URI's default store for this secret.";
                      };
                      item = lib.mkOption {
                        type = lib.types.str;
                        default = "";
                        description = "Item name or id holding the secret.";
                      };
                      field = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = "Field label within the item.";
                      };
                      section = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = "Section within the item (requires field).";
                      };
                    };
                  }
                );
                default = null;
                example = {
                  vault = "Infra";
                  item = "Postgres";
                  field = "connection-url";
                };
                description = ''
                  Point at a secret that already exists in the provider store,
                  instead of the conventional secretspec/{project}/{profile}/{key}
                  location. A native op:// reference translates as
                  op://vault/item/field -> { vault; item; field; }.
                '';
              };
            };
          }
        )
      );
      default = { };
      description = "Declared secrets, keyed by secret name (becomes the environment variable name).";
    };

    providers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            uri = lib.mkOption {
              type = lib.types.str;
              default = "";
              example = "onepassword://Infra";
              description = "Provider URI (e.g., onepassword://vault, keyring://, sops://file).";
            };
            credentials = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              example = {
                service_account_token = "env";
              };
              description = "Provider credentials and the source each is read from.";
            };
          };
        }
      );
      default = { };
      description = "Named provider aliases usable in entry fallback chains.";
    };

    scopes = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            secrets = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Names of the entries this scope exposes.";
            };
          };
        }
      );
      default = { };
      description = ''
        Allowlists restricting which secrets each service receives. Scopes
        minimize delivery; they are not an authorization boundary.
      '';
    };

    defaultProviders = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "team" ];
      description = "Provider fallback chain for entries that do not set their own providers.";
    };
  };
}
