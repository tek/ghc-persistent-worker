# Nix expression to build Buck2 from source.
# Based, in part, on https://github.com/thoughtpolice/buck2-nix/blob/c602d0f44f03310a89f209a322bb122b0d3c557a/buck/nix/buck2/default.nix
#
# To update Buck2:
# - change the `git_rev` and `src.hash` attributes below.
# - copy a fresh `Cargo.lock` from Buck2.
{
  lib,
  fetchFromGitHub,
  makeBinaryWrapper,
  installShellFiles,
  fenix,
  makeRustPlatform,
  openssl,
  pkg-config,
  protobuf,
  sqlite,
  fetchpatch,
  watchman,
}:
let
  rustPlatform = makeRustPlatform {
    cargo = toolchain;
    rustc = toolchain;
  };
  pname = "buck2";
  git_rev = "2026-01-19";

  src = fetchFromGitHub {
    owner = "facebook";
    repo = pname;
    rev = git_rev;
    hash = "sha256-5SfYIYrvZoXGYSB4PGGWYrnsbCy3hwFZTx1QYIflJGE=";
  };

  toolchain = fenix.fromToolchainFile {
    dir = src;
    sha256 = "sha256-Lz2Wx4xpZH0Nwgmq5VMVB5PsEJiPoQEXZ8OZCRUXPgE=";
  };
in
rustPlatform.buildRustPackage {
  inherit pname src;
  version = "git-${git_rev}";

  patches = [
    ./0001-feat-support-configuring-the-manifold-URL.patch
    ./0002-A-B-C-is-a-valid-name-for-A-B-C-C.patch
    ./0003-Only-show-test-output-by-default-configurable.patch
    ./0004-Test-caching-dice.patch
    ./0005-Test-caching-remote.patch
    ./0006-Allow-all-tests-on-RE.patch
    ./0007-disable-dep-file-check-for-now.patch
    ./0008-remote_execution-Retry-BatchReadBlobs-requests-buck2.patch
    ./0009-Disable-cell-segmentation-indiscriminately-as-a-work.patch
    ./0010-Add-debugging-output-for-RE-actions.patch
    ./0011-WIP-Retry-Bazel-Remote-API-requests-if-possible.patch
    ./0012-Add-rpc-timeout-config-and-wire-it-up.patch
    ./0013-Inspect-error-chain-for-root-cause.patch
    ./0014-Handle-Cancelled-error-code-and-retry.patch
    ./0015-Use-max_retries-setting.patch
    ./0016-Retry-request-immediately-for-deadline-exceeded-time.patch
    ./0017-Use-retry-for-batch_read_blobs.patch
    ./0018-Do-not-set-a-timeout-on-the-gRPC-message-itself.patch
    ./0019-Set-tcp_keepalive-to-180-seconds.patch
    ./0020-Print-method-for-RPC-retries.patch
    ./0021-fixup.patch
    ./0022-Fix-find_missing_cache-LRU-size-from-52M-entries-to-.patch
  ];

  cargoLock = {
    lockFile = ./Cargo.lock;
    allowBuiltinFetchGit = true;
  };

  postPatch = ''
    cp ${./Cargo.lock} Cargo.lock
    chmod +w Cargo.lock  # Huh???
  '';

  nativeBuildInputs = [
    installShellFiles
    protobuf
    pkg-config
    makeBinaryWrapper
  ];

  buildInputs = [
    openssl
    sqlite
  ];

  BUCK2_BUILD_PROTOC = "${protobuf}/bin/protoc";
  BUCK2_BUILD_PROTOC_INCLUDE = "${protobuf}/include";

  doCheck = false;
  dontStrip = true; # XXX (aseipp): cargo will delete dwarf info but leave symbols for backtraces

  postInstall = ''
    mv $out/bin/buck2     $out/bin/buck
    ln -sfv $out/bin/buck $out/bin/buck2
    mv $out/bin/starlark  $out/bin/buck2-starlark
    mv $out/bin/read_dump $out/bin/buck2-read_dump

    installShellCompletion --cmd buck2 \
      --bash <( $out/bin/buck2 completion bash ) \
      --fish <( $out/bin/buck2 completion fish ) \
      --zsh <( $out/bin/buck2 completion zsh )

    # We wrap the buck2 so that it can never not have a watchman. This allows
    # for nix run .#buck2-source to work.
    wrapProgram $out/bin/buck \
      --prefix PATH : ${lib.makeBinPath [ watchman ]}
  '';

  meta = with lib; {
    description = "Build system, successor to Buck";
    homepage = "https://buck2.build/";
    changelog = "https://github.com/facebook/buck2/blob/main/CHANGELOG.md";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = platforms.linux ++ platforms.darwin;
    mainProgram = "buck2";
  };
}
