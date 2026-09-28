# Option namespace shared by the NixOS and Home Manager classes. Included via
# imports from each class module; the substrate secrets extension pushes those
# modules into the appropriate configurations, so any class module can declare
# secrets without referencing the extension itself.
{ lib, ... }:
{
  options.substrate.secrets = {
    entries = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
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

            providers = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [
                "team"
                "keyring"
              ];
              description = ''
                Ordered fallback chain of provider aliases (from substrate.secrets.providers)
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
