{
  description = "GHC persistent worker";

  inputs.hix.url = "github:tek/hix/package-set-overrides";
  inputs.ghc-debug = {
    url = "git+https://gitlab.haskell.org/ghc/ghc-debug";
    flake = false;
  };
  inputs.fenix = {
    url = "github:nix-community/fenix/9d17341a4f227fe15a0bca44655736b3808e6a03";
    inputs.nixpkgs.follows = "hix/nixpkgs";
  };

  outputs = {hix, ghc-debug, fenix, ...}: let

    testEnv = config: {
      ghc_dir = "${config.toolchain.vanilla.ghc}";
    };

    sharedExeOverrides = {modify, hsLibC, ...}: {
      ghc-worker = modify hsLibC.enableSharedExecutables;
    };

    envOverrides = config: {overrideAttrs, notest, nodoc, ...}: {
      ghc-worker = nodoc (overrideAttrs (testEnv config));
      buck-worker-internal = nodoc;
      buck-worker-proto = nodoc;
      buck-worker-types = nodoc;
    };

    ipeOverrides = {ghcOptions, ...}: let
      opts = ghcOptions ["-finfo-table-map" "-fdistinct-constructor-tables"];
    in {
      ghc-worker = opts;
      buck-worker-internal = opts;
      buck-worker-proto = opts;
      buck-worker-types = opts;
      debug = opts;
    };

    buckBinOverrides = {overrideAttrs, notest, nodoc, ...}: {
      ghc-worker = notest;
    };

    overrides_mwb_flag = extra: {enable, ...}: let

      flags = builtins.foldl' (z: flag: enable flag z) (enable "mwb") extra;

    in {
      buck-worker-types = flags;
      buck-worker-internal = flags;
      ghc-worker = flags;
    };

    commonOverrides = flags: args: [
      sharedExeOverrides
      (envOverrides args.config)
      (overrides_mwb_flag flags)
    ];

  in hix ({config, build, lib, util, ...}: let

    globalConfig = config;

    localOptions.options = {

      buckGhc = lib.mkOption {
        description = "Which of our branches to use for the buck build";
        type = lib.types.enum ["mwb" "mwb-25-07" "mwb-25-07-no-ipe" "mwb-25-10"];
        default = "mwb-25-07";
      };

    };

  in {
    imports = [localOptions];

    compiler = "ghc910";
    ghcVersions = [];
    main = "ghc-worker";
    ghci.args = ["-package ghc" "-DMWB" "-DMWB_2025_07" "-DUNIT_INDEX"];
    hls.genCabal = false;

    compilers = {

      # Roughly the GHC used by MWB.
      mwb.source.build = {
        url = "https://gitlab.haskell.org/ghc/ghc";
        version = "9.10.1";
        flavour = "release+split_sections+ipe";
        rev = "f20cef54770b530e3e08183ce1f846fc734fe901";
        hash = "sha256-SOw74r52spFqJpW97G9Ca84ib1/7ga3Ylyq314DshGk=";
      };

      # Similar to `mwb`, but using the latest versions of the bytecode patches.
      mwb-25-07-ipe.source.build = {
        url = "https://gitlab.haskell.org/ghc/ghc";
        version = "9.10.1";
        flavour = "release+split_sections+ipe";
        rev = "66c776ea948bc442ea6a0c8ad1e2cd6de2fb98dd";
        hash = "sha256-+WrkO+fHL96DSXcDPrt6JLhgkRQa42g6+lr8s30JCLA=";
      };

      mwb-25-07-no-ipe = {
        extends = "mwb-25-07-ipe";
        source.build.flavour = "release+split_sections";
      };

      # More recent GHC that includes fixed module graph nodes, with all of the custom patches present in `mwb-25-07`.
      mwb-25-10-ipe.source.build = {
        url = "https://gitlab.haskell.org/ghc/ghc";
        version = "9.12.1";
        flavour = "release+split_sections+ipe";
        rev = "99d4164fcd5cbc23c1f00bf5fd2e8f710d10bf16";
        hash = "sha256-yN0jQJiVAcBNCpHUpxPzFSGgY4TAO0xpfdzQl9L5lgs=";
      };

      mwb-26-01-ipe.source.build = {
        url = "https://gitlab.haskell.org/ghc/ghc";
        version = "9.10.1";
        flavour = "release+split_sections+ipe";
        rev = "b989904c813530b7f7c11da9de0ba641004aa29f";
        hash = "sha256-gyAAk7fkxK69talyhEZo7ZHZAd2QUQXOvyOjOAweeXU=";
      };

    };

    buckGhc = "mwb-25-07";

    envs.ghc910 = args: {
      env = testEnv args.config;
      expose.scoped = true;
      overrides = [(envOverrides args.config) ({notest, ...}: { ghc-worker = notest; })];
    };

    envs.dev = args: {
      env = testEnv args.config;
      hls.enable = lib.mkForce false;
      package-set.extends = "mwb-25-07";
      overrides = commonOverrides ["unit-index" "downsweep-cache" "mwb-25-07"] args ++ [ipeOverrides];
      buildInputs = pkgs: [pkgs.zlib pkgs.snappy pkgs.protobuf pkgs.hixPackages.proto-lens-protoc];
    };

    envs.mwb = args: {
      expose.scoped = true;
      env = testEnv args.config;
      package-set.extends = "mwb";
      overrides = commonOverrides ["unit-index" "downsweep-cache" "mwb"] args ++ [buckBinOverrides];
    };

    envs.mwb-25-07 = args: {
      expose.scoped = true;
      env = testEnv args.config;
      package-set.extends = "mwb-25-07";
      overrides = commonOverrides ["unit-index" "downsweep-cache" "mwb-25-07"] args ++ [buckBinOverrides ipeOverrides];
    };

    envs.mwb-25-10 = args: {
      expose.scoped = true;
      env = testEnv args.config;
      package-set.extends = "mwb-25-10";
      overrides = commonOverrides ["mwb-25-10"] args ++ [buckBinOverrides ipeOverrides];
      packages = [
        "ghc-worker"
        "buck-proxy"
        "buck-worker-internal"
        "buck-worker-grpc"
        "buck-worker-proto"
        "buck-worker-types"
      ];
    };

    envs.mwb-26-01 = args: {
      expose.scoped = true;
      env = testEnv args.config;
      package-set.extends = "mwb-26-01";
      overrides = commonOverrides ["unit-index" "downsweep-cache" "mwb-25-07" "mwb-26-01"] args ++ [buckBinOverrides ipeOverrides];
    };

    envs.profiled = args: {
      env = testEnv args.config;
      package-set.extends = "mwb-25-07";
      overrides = commonOverrides ["unit-index" "mwb-25-07"] args ++ [ipeOverrides];
    };

    envs.cabal-build = {
      expose.shell = true;
      package-set.compiler.source = "ghc910";
      package-set.overrides = lib.mkForce [];
      package-set.extraOverrides = lib.mkForce [];
      packages = [];
      buildInputs = pkgs: [pkgs.zlib pkgs.snappy pkgs.protobuf];
    };

    # ------------------------------------------------------------------------------------------------------------------
    # Buck

    # The environment for the CLI tool `buck`, using the Buck overlay extracted from MWB.
    # `fenix` is a dep of Buck.
    # Exposes a devShell named `buck` that should be used to gain access to the CLI tool.
    envs.buck = {
      package-set.compiler.source = "ghc910";
      expose.shell = true;
      packages = [];
      buildInputs = pkgs: [pkgs.buck2-source];

      package-set.compiler.nixpkgs.overlays = [
        fenix.overlays.default
        (import ./ops/buck/overlay.nix)
      ];
    };

    # The environment for our Buck nixpkgs integration, from which GHC and the package set are taken when exposing them
    # in `outputs.packages` below.
    # Uses our custom GHC build and injects a hook into all Haskell derivations that creates `package.cache` in the
    # store dir, which is needed because Buck supplies individual package DBs to GHC.
    envs.buck-build = {config, ...}: {
      packages = [];
      package-set.extends = globalConfig.buckGhc;
      env = testEnv config;

      overrides = api@{override, ...}: let
        testDeps = import ./ops/test-deps.nix { inherit util; };
      in testDeps.overrides api // {
        __all = override (drv: {
          postInstall = (drv.postInstall or "") + ''
            ghc-pkg recache --package-db $packageConfDir
          '';
        });
      };
    };

    # The interface that Buck expects when loading Nix packages in `toolchains/BUCK` using those `nix.rules.flake`
    # rules.
    # Exposes the toolchain Haskell packages listed in `./ops/ghc-toolchain-libraries.nix` in the attribute
    # `haskellPackages.libs` as well as Python and the GHC compiler derivation.
    outputs.packages =
      import ./ops/buck/packages.nix { inherit config lib; };

    # ------------------------------------------------------------------------------------------------------------------

    envs.hls-db = {
      package-set.extends = "mwb-25-07";
    };

    envs.hls = {
      package-set.extends = "mwb-25-07";

      overrides = {hackage, fast, force, unbreak, nobench, notest, source, modify, hsLibC, disable, drv, ...}: let

        github = {owner ? "tek", repo, rev, hash, path ? ""}:
          fast (unbreak (nobench (notest (source.sub (config.pkgs.fetchFromGitHub { inherit owner repo rev hash; }) path))));

        rev = "3cde227b7953fde0fccd1672151270fb1d168309";
        hash = "sha256-cQFjO/ECurFyJGkiZf3J05Q5UYyy74hgnm6XTurrs0Q=";

        hlsPackage = path: github {
          repo = "haskell-language-server";
          inherit rev hash;
          inherit path;
        };

      in {

        binary-instances = force;

        cabal-add = fast (force (hackage "0.2" "0yxh19iqspai0003p83rsnqkhq2dxa3a2vz3qfzg3k4392z1zbvi"));

        haskell-language-server =
          lib.foldl (lib.flip disable) (modify hsLibC.enableSharedExecutables (hlsPackage "")) [
            "stan" "stylishHaskell" "ormolu" "fourmolu" "hlint"
          ];
        ghcide = hlsPackage "ghcide";
        hls-graph = hlsPackage "hls-graph";
        hls-plugin-api = hlsPackage "hls-plugin-api";
        hls-test-utils = hlsPackage "hls-test-utils";

        hie-bios = github {
          repo = "hie-bios";
          rev = "6847c318cb8524f1d46d2bf02b991318253cef9b";
          hash = "sha256-rR8b2g6Req5Ssr4TtfMCNQZFqRrgG0S+pMj06KkE+q4=";
        };

        Diff = hackage "0.5" "13n231179wa9xm2933f328v00jb486w740yahz4qcbza4yv39w1i";
        directory-ospath-streaming = hackage "0.3" "0m0v200mgmkizm3l6pw9x9gvqx9xancgsal4z1pb7hi2pgrj0w0d";
        fourmolu = drv null;
        ghc-lib-parser = hackage "9.12.2.20250421" "0qxi41zr50chrr6isyfpff5kq6kqxhc5iri6a8ixvz27042a0hsq";
        ghc-lib-parser-ex = hackage "9.12.0.0" "1kxdwr1vpjn4rlhbvajdh25zjl3wyl8lli0krmdxlp03jg4p2vlx";
        hiedb = notest (hackage "0.7.0.0" "0i6szmajpg1w2mi29vs2z3brjhznivaq2his6zcz38gpyfr2dlwi");
        hlint = drv null;
        ormolu = drv null;
        stan = drv null;
        stylish-haskell = drv null;

      };
    };

    # Use GHC 9.8 for `cabal-install` and other build tools because:
    # - If we used the same GHC as the build (i.e. MWB branch), any time the GHC changes, Cabal would be rebuilt, which
    #   is time-consuming.
    # - If we used GHC 9.10 (matching the MWB version), the build GHC's libraries would be shadowed by those used to
    #   build Cabal, because the nixpkgs GHC derivation doesn't set the proper hash suffix.
    #   This is fixed in nixpkgs upstream.
    envs.hix-build-tools.package-set.compiler.source = "ghc98";

    output.extraPackages = ["ghc-debug-brick" "eventlog2html" "hp2pretty" "ghc-events"];

    commands = let

      testNames = lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./ops/buck-test));

      buck-test = import ./ops/buck-test/default.nix { inherit util; };

      buckTest = name: {
        expose = true;
        env = "buck";
        command = buck-test name (import ./ops/buck-test/${name}/default.nix { inherit util; });
      };

    in lib.genAttrs testNames buckTest // {
      hls.env = "hls-db";
    };

    packages = {

      ghc-worker = {
        src = ./ghc-worker;
        cabal.meta.synopsis = "Buck2 GHC persistent worker";
        cabal.ghc-options-exe = [
          "-O2"
          "-threaded"
          "-rtsopts"
          ''"-with-rtsopts=-K512M -I5 -A128M -T -N"''
        ];

        library = {
          enable = true;
          dependencies = [
            "async"
            "binary"
            "buck-worker-grpc"
            "buck-worker-internal"
            "buck-worker-proto"
            "buck-worker-types"
            "bytestring"
            "containers"
            "deepseq"
            "directory"
            "filepath"
            "ghc"
            "ghc-debug-stub"
            "grapesy"
            "process"
            "stm"
            "text"
            "unix"
          ];
        };

        executables.ghc-worker = {
          source-dirs = "app/ghc-worker";
        };

        test = {
          enable = true;
          dependencies = [
            "buck-worker-internal"
            "buck-worker-types"
            "containers"
            "directory"
            "filepath"
            "ghc"
            "temporary"
            "text"
            "typed-process"
          ];
          source-dirs = "test";
          dependOnLibrary = false;
        };
      };

      debug = {
        src = ./debug;
        cabal.dependencies = ["ghc-debug-client" "ghc-debug-common" "ghc-debug-stub" "containers"];
        executable.enable = true;
        executables.snapshot = {
          dependencies = ["directory" "filepath"];
        };
        executables.gen-case = {};
      };

      buck-proxy = {
        src = ./buck-proxy;
        cabal.meta.synopsis = "Buck2 GHC persistent worker";
        library = {
          enable = true;
          dependencies = [
            "buck-worker-grpc"
            "buck-worker-proto"
            "buck-worker-types"
            "containers"
            "directory"
            "grapesy"
            "process"
            "text"
          ];
        };
        executables.buck-proxy = {
          dependencies = [
            "buck-worker-types"
            "unix"
          ];
          ghc-options-exe = [
            "-O2"
            "-threaded"
            "-rtsopts"
            ''"-with-rtsopts=-K512M -H -I5 -T -N"''
          ];
          source-dirs = "app/buck-proxy";
        };
      };

      instrument = {
        src = ./instrument;
        cabal.meta.synopsis = "Buck2 GHC persistent worker instrumentation client";
        executable = {
          dependencies = [
            "binary"
            "brick"
            "buck-worker-internal"
            "buck-worker-proto"
            "buck-worker-types"
            "bytestring"
            "containers"
            "ghc-debug-brick"
            "directory"
            "filepath"
            "fsnotify"
            "grapesy"
            "microlens-platform"
            "text"
            "time"
            "vty"
          ];
          ghc-options-exe = [
            "-O2"
            "-threaded"
            "-rtsopts"
            ''"-with-rtsopts=-K512M -H -I5 -T -N"''
          ];
          source-dirs = ".";
        };
      };

      buck-worker-internal = {
        src = ./internal;
        library = {
          enable = true;
          dependencies = [
            "aeson"
            "buck-worker-types"
            "containers"
            "directory"
            "exceptions"
            "filepath"
            "ghc"
            "ghc-boot"
            "time"
            "transformers"
          ];
          source-dirs = "src";
          ghc-options = ["-O2"];
        };
      };

      buck-worker-proto = {
        src = ./proto;
        library = {
          enable = true;
          dependencies = [
            "bytestring"
            "containers"
            "deepseq"
            "grapesy"
            "lens-family"
            "proto-lens"
            "text"
            "vector"
          ];
          source-dirs = "src";
          ghc-options = ["-O2"];
        };
      };

      buck-worker-types = {
        src = ./types;
        library = {
          enable = true;
          dependencies = [
            "aeson"
            "binary"
            "containers"
            "filepath"
            "ghc"
            "split"
            "text"
          ];
          source-dirs = "src";
          ghc-options = ["-O2"];
        };
      };

      buck-worker-grpc = {
        src = ./grpc;
        library = {
          enable = true;
          dependencies = [
            "buck-worker-types"
            "buck-worker-proto"
            "containers"
            "grapesy"
            "text"
          ];
          source-dirs = "src";
          ghc-options = ["-O2"];
        };
      };

    };

    package-sets.mwb = {
      compiler = "mwb";
    };

    package-sets.mwb-25-07-no-ipe = {
      compiler = "mwb-25-07-no-ipe";
    };

    package-sets.mwb-25-07 = {
      compiler = "mwb-25-07-ipe";
    };

    package-sets.mwb-25-10 = {
      compiler = "mwb-25-10-ipe";
      overrides = {hackage, force, source, notest, ...}: let

        github = {owner ? "tek", repo, rev, hash, path ? ""}:
          force (source.sub (config.pkgs.fetchFromGitHub { inherit owner repo rev hash; }) path);

      in {
        ChasingBottoms = force;
        __all = notest;
        aeson = force (hackage "2.2.3.0" "1a9a0z6ljbck5scwkk9r9p04y9avn9vja3n063lyqgn2v1vjb1sp");
        bitwise = force;
        boring = force;
        cborg = force;
        foldl = force;
        generic-deriving = force;
        ghc-source-gen = github {
          repo = "ghc-source-gen";
          rev = "fd010ca5229a8ff0231a0af36bd17bcf7d0c976f";
          hash = "sha256-I+SeSO/eX/jCUhtmGVljcN+FspkSEWS6WTaU9ktGurg=";
        };
        happy = notest;
        hashable = force (hackage "1.5.0.0" "1hh22f23apsjrn3h36vzw9871jqw6y4r4di1351qs5mqqabhd011");
        hedgehog = force;
        http-types = notest;
        indexed-traversable = force;
        indexed-traversable-instances = force;
        integer-conversion = force;
        integer-logarithms = hackage "1.0.4" "0yyj0g5xkm1pjkkr4smf25lpzc936df0fyc4nsj4bx145ggspx3k";
        invariant = force;
        lens = notest (hackage "5.3.5" "0cbpvsyc9nk0v6n2zcgvcjnzp7pxffnv285jdn6gldrw9pksbkpf");
        lifted-base = force;
        proto-lens-setup = github {
          repo = "proto-lens";
          rev = "901331d19c3ab90ec24e231fa69c9ed81204f73b";
          path = "proto-lens-setup";
          hash = "sha256-st+j4vK4N00xHB//b62/HPLRBUw/PRGL8bP8WECMU5U=";
        };
        scientific = force;
        semialign = force;
        strict = force;
        th-abstraction = notest (hackage "0.7.1.0" "09wr7x9bpzyrys8id1mavk9wvqhh2smxdkfwi82kpcycm7a1z7sx");
        th-compat = force;
        these = force;
        time-compat = force;
        unordered-containers = notest;
        uuid-types = force;
        witherable = force;
        zlib = force;
      };
    };

    overrides = {hackage, force, source, notest, ...}: {
      auto-update = hackage "0.2.6" "0sp25j3fcgmfr2zv1ccg1id1iynj3azinjg23g0vy1m1m7gnmkzi";
      eventlog2html = hackage "0.11.1" "0l4klmfsxmikh8x7rp7l3s5sycwq2xmqz3d1p6078pcygjkzc6fv";
      ghc-debug-brick = source.sub ghc-debug "ghc-debug-brick";
      ghc-debug-client = force (source.sub ghc-debug "client");
      ghc-debug-common = force (source.sub ghc-debug "common");
      ghc-debug-convention = force (source.sub ghc-debug "convention");
      ghc-debug-stub = source.sub ghc-debug "stub";
      grapesy = force (hackage "1.0.1" "0j7w0knclrhxc5h1vlbdpwvvpz6ixjw6flqfhdgk6xw30g7cwf5m");
      grpc-spec = notest (hackage "1.0.0" "0pgq63k6p65c5ffzxwihp8j1p731qrnda5rxrzqsylanmdmnvjb8");
      hinotify = hackage "0.4.2" "072i8d9khxwra5x05bxxm6018ga3sjf7kykxqc6km7vi01wh2h1b";
      http-semantics = hackage "0.3.0" "0ghj37jr5bsz047p6i66ddkwc9mxkfpbw14nd54slmj1lpwn5z4a";
      http2 = force (hackage "5.3.10" "025l7sxg9jhhkhxzlhylnh2b1phdk3vml3m573lvldcy812hpvjk");
      http2-tls = force;
      network = hackage "3.2.7.0" "08frm9gm422b9aqlmmzflj0yr80ic0ip8s4gsmr0izhizzab5420";
      network-control = hackage "0.1.7" "0p46ymb8565909q2qzig02q91ch8c4zrkminvma1iizb3s2d81m8";
      network-run = hackage "0.4.4" "0c2wpm9bkizaw9sbhy9yi51m04cjlbvzdjw09s5gy74wz2pz4spw";
      proto-lens = force;
      proto-lens-protobuf-types = force;
      proto-lens-protoc = force (hackage "0.9.0.0" "18b0hz5z4cfimnbhjnhdk4lf2r0wy5aardngdhyy8aqvr62v5r62");
      proto-lens-runtime = force;
      proto-lens-setup = force;
      serialise = force;
      snappy-c = force;
      time-manager = hackage "0.2.2" "1ja8pimvy07b05ifkrg6q0lzs3kh0k2dmncwjdxl81199r559vf5";
      tls = hackage "2.1.6" "11rxsmwhv6g4298a0355v6flz4n6gw64qw3iha7z0ka3nv7vq4vv";
      uuid = force;
    };

    package-sets.mwb-26-01 = {
      compiler = "mwb-26-01-ipe";
    };

    internal.hixCli.dev = true;

    outputs.apps.rebuild-impure-worker = util.app (util.zscript "rebuild-impure-worker" ''
    if [[ -z $1 ]]
    then
      echo "Usage: nix run .#rebuild-impure-worker GHC_BUILD_DIR [DEV_SHELL]"
      exit 1
    fi
    dir=$1
    nix develop .#''${2-cabal-build} -c cabal build -fmwb -funit-index -fdownsweep-cache $@[3,$] -w $dir/stage1/bin/ghc ghc-worker
    print 'Worker executable:'
    cabal -v0 list-bin ghc-worker
    '');

    cabal = {
      author = "Ian-Woo Kim";
      license = "MIT";
      license-file = "LICENSE";
      meta.maintainer = "ianwookim@gmail.com";
      language = "GHC2021";

      default-extensions = [
        "BlockArguments"
        "DerivingStrategies"
        "DuplicateRecordFields"
        "LambdaCase"
        "OverloadedLists"
        "NamedFieldPuns"
        "OverloadedRecordDot"
        "OverloadedStrings"
        "RecordWildCards"
        "StrictData"
        "TypeFamilies"
        "DataKinds"
      ];

      ghc-options = [
        "-Wall"
        "-Widentities"
        "-Wincomplete-uni-patterns"
        "-Wmissing-deriving-strategies"
        "-Wredundant-constraints"
        "-Wunused-type-patterns"
        "-Wunused-packages"
      ];

      meta = {

        flags = {

          mwb = {
            description = "Use mwb-customized GHC";
            manual = true;
            default = false;
          };

          mwb-25-07 = {
            description = "Use mwb-customized GHC from July 2025";
            manual = true;
            default = false;
          };

          mwb-25-10 = {
            description = "Use mwb-customized GHC (9.12) from October 2025";
            manual = true;
            default = false;
          };

          mwb-26-01 = {
            description = "Use mwb-customized GHC from January 2026";
            manual = true;
            default = false;
          };

          downsweep-cache = {
            description = "GHC contains the patch for using an old module graph as a cache for downsweep";
            manual = true;
            default = false;
          };

          unit-index = {
            description = "GHC contains the patch for the abstraction of parts of the unit state";
            manual = true;
            default = false;
          };

        };

        when = [
          {
            condition = "flag(mwb)";
            cpp-options = ["-DMWB"];
          }
          {
            condition = "flag(mwb-25-07)";
            cpp-options = ["-DMWB_2025_07"];
          }
          {
            condition = "flag(mwb-25-10)";
            cpp-options = ["-DMWB_2025_10"];
          }
          {
            condition = "flag(mwb-26-01)";
            cpp-options = ["-DMWB_2026_01"];
          }
          {
            condition = "flag(downsweep-cache)";
            cpp-options = ["-DDOWNSWEEP_CACHE"];
          }
          {
            condition = "flag(unit-index)";
            cpp-options = ["-DUNIT_INDEX"];
          }
        ];

      };

    };

  });

}
