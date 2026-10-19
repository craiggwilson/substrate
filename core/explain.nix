# Where does my configuration land?
#
# The question this answers is "why is my host getting this, and why isn't it
# getting that". A finder is a function from the host and user configurations to
# a list of module tree nodes, and nothing about that is observable from outside
# substrate: the finder runs inside a builder, its result goes straight into
# `nixosSystem`, and the only failure mode is a missing option.
#
# This module answers it by running the same finder over the same arguments a
# builder would and reporting what came back, keyed by the address every tree
# node already carries. `available` alongside `selected` is the useful part: the
# difference between them is what the finder filtered out, which is otherwise
# invisible.
#
# It is a global output because it needs no package set -- `nix eval .#explain`
# is the whole workflow.
{ lib, config, ... }:
let
  inherit (config.substrate) settings;

  allClasses = [ "generic" ] ++ settings.supportedClasses;

  finder = config.substrate.moduleFinders.${settings.modulesFinder};

  # A node counts toward a class when it carries that class's config. `generic`
  # counts toward every class, which is what extraction does when it merges
  # generic modules in -- without that, a module written only in generic terms
  # would look as though it reached no class at all.
  carries =
    class: node:
    (node ? ${class} && node.${class} != null)
    || (class != "generic" && node ? generic && node.generic != null);

  # The finder, called with the same argument shapes a class builder uses.
  # `hosts.<name>.users` holds names, so the configs are resolved here rather
  # than carried around.
  #
  # This asks the finder which nodes it returns rather than calling
  # findModulesForClass, because that returns the module bodies a class
  # configuration would be built from. What is worth reporting is the node and
  # its address.
  selectedFor =
    class: cfgs: map (node: node.__path) (builtins.filter (carries class) (finder.find cfgs));

  # The scopes a class builder actually calls the finder with.
  #
  #   <host>        [ host ]                    the host on its own
  #   <host>+users  [ host ] ++ all its users   a host class building for a host
  #                                              that has users
  #   <host>/<user> [ host, user ]              home-manager, one user at a time
  #
  # The second and third are different calls, not approximations of each other: a
  # conditional that looks at one user sees a different list under each, which is
  # the usual reason a module lands where nobody expected.
  usersOf = host: map (name: config.substrate.users.${name}) host.users;

  classesFor =
    class: host:
    let
      userConfigs = usersOf host;
    in
    {
      ${host.name} = selectedFor class [ host ];
      "${host.name}+users" = selectedFor class ([ host ] ++ userConfigs);
    }
    // lib.listToAttrs (
      map (
        user:
        lib.nameValuePair "${host.name}/${user.name}" (
          selectedFor class [
            host
            user
          ]
        )
      ) userConfigs
    );

  # Everything the finder could have returned, for the diff.
  available = map (node: node.__path) (config.substrate.moduleFinders.all.find [ ]);

  perClass = lib.genAttrs allClasses (
    class:
    # mapAttrs passes name then value, so the host is the second argument.
    lib.mapAttrs (_: host: classesFor class host) (
      lib.filterAttrs (_: host: !host.usersOnly) config.substrate.hosts
    )
  );
in
{
  config.substrate.outputs.global.explain = [
    {
      build = _: {
        inherit (settings) modulesFinder;
        inherit available;
        classes = perClass;
      };
    }
  ];
}
