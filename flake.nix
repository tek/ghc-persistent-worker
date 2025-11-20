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

    overrides_mwb_flag = extra: {enable, ...}: {
      buck-worker-internal = enable extra (enable "mwb");
    };

    commonOverrides = branch: args: [
      sharedExeOverrides
      (envOverrides args.config)
      (overrides_mwb_flag branch)
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
    ghci.args = ["-package ghc"];
    hls.genCabal = false;

    compilers = {

      mwb.source.build = {
        url = "https://gitlab.haskell.org/ghc/ghc";
        version = "9.10.1";
        flavour = "release+split_sections+ipe";
        rev = "75206a243dc7ad43867582c6bb8ffd51878f8a7e";
        hash = "sha256-OHd9kmG2ReOd/FerRXAEHmKuiHu/Se/Uv7OfgvJzBoI=";
      };

      mwb-25-07-ipe.source.build = {
        url = "https://gitlab.haskell.org/ghc/ghc";
        version = "9.10.1";
        flavour = "release+split_sections+ipe";
        rev = "e5fb170e47efa851ad43659899feb1f53017d127";
        hash = "sha256-1ekDaHeoUmYQlNAyDak3YOdXAyN18q50Yc+poGD6LWY=";
      };

      mwb-25-07-no-ipe = {
        extends = "mwb-25-07-ipe";
        source.build.flavour = "release+split_sections";
      };

      mwb-25-10-ipe.source.build = {
        url = "https://gitlab.haskell.org/ghc/ghc";
        version = "9.12.1";
        flavour = "release+split_sections+ipe";
        rev = "99d4164fcd5cbc23c1f00bf5fd2e8f710d10bf16";
        hash = "sha256-yN0jQJiVAcBNCpHUpxPzFSGgY4TAO0xpfdzQl9L5lgs=";
      };

    };

    buckGhc = "mwb-25-07";

    envs.ghc910 = args: {
      env = testEnv args.config;
      hls.enable = lib.mkForce false;
      expose.scoped = true;
    };

    envs.dev = args: {
      env = testEnv args.config;
      hls.enable = lib.mkForce false;
      package-set.extends = "mwb-25-07";
      overrides = commonOverrides "mwb-25-07" args ++ [ipeOverrides];
    };

    envs.mwb-25-07 = args: {
      expose.scoped = true;
      env = testEnv args.config;
      package-set.extends = "mwb-25-07";
      overrides = commonOverrides "mwb-25-07" args ++ [buckBinOverrides ipeOverrides];
    };

    envs.mwb-25-10 = args: {
      expose.scoped = true;
      env = testEnv args.config;
      package-set.extends = "mwb-25-10";
      overrides = commonOverrides "mwb-25-10" args ++ [buckBinOverrides ipeOverrides];
      packages = [
        "ghc-worker"
        "buck-proxy"
        "buck-worker-internal"
        "buck-worker-grpc"
        "buck-worker-proto"
        "buck-worker-types"
      ];
    };

    envs.mwb = args: {
      expose.scoped = true;
      env = testEnv args.config;
      package-set.extends = "mwb";
      overrides = commonOverrides "mwb" args ++ [buckBinOverrides];
    };

    envs.profiled = args: {
      env = testEnv args.config;
      package-set.extends = "mwb-25-07";
      overrides = commonOverrides "mwb-25-07" args ++ [ipeOverrides];
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

    envs.hls-db = {};

    envs.hls.compiler = "ghc910";

    envs.hix-build-tools.package-set.extends = "mwb-25-07";

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
          ''"-with-rtsopts=-K512M -H -I5 -T -N"''
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
            "deepseq"
            "directory"
            "exceptions"
            "filepath"
            "ghc"
            "time"
            "transformers"
          ];
          source-dirs = "src";
          ghc-options = ["-O2"];
        };

        cabal = {

          meta.flags = {

            mwb = {
              description = "use mwb-customized GHC";
              manual = true;
              default = false;
            };

            mwb-25-07 = {
              description = "use mwb-customized GHC from July 2025";
              manual = true;
              default = false;
            };

            mwb-25-10 = {
              description = "use mwb-customized GHC from October 2025";
              manual = true;
              default = false;
            };

          };

          component.when = [
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
          ];

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
    };

    internal.hixCli.dev = true;

    # Create two result links for the worker binaries that can be used in MWB with something like:
    # impure_worker(
    #    name = "impure_ghc_worker",
    #    binary_path = "/path/to/persistent-worker/result-no-ipe-ghc-worker/bin/ghc-worker",
    # )
    # The env `no-ipe` is used because unlike the test projects here, MWB doesn't use the custom GHC defined here, so
    # building the worker with IPE will cause some problems.
    outputs.apps.build-mwb-links = util.app (util.zscript "build-mwb-links" ''
    nix build --out-link result-no-ipe-buck-proxy .#no-ipe.buck-proxy
    nix build --out-link result-no-ipe-ghc-worker .#no-ipe.ghc-worker
    '');

    outputs.apps.build-mwb-links-ipe = util.app (util.zscript "build-mwb-links-ipe" ''
    nix build --out-link result-ipe-buck-proxy .#ipe.buck-proxy
    nix build --out-link result-ipe-ghc-worker .#ipe.ghc-worker
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
    };

  });

}
