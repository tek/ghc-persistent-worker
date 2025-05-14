# Run this with `nix run .#reexport`
#
# Test that the make state is restored from the Buck cache when recompiling a changed module after that module had been
# built successfully previously, for the specific case of reexporting a class from an external dependency.
{util}: let

  inherit (util) pkgs;

in pkgs.writeScript "reexport" ''
#!${pkgs.runtimeShell}
set -e

dir=$(mktemp -d --tmpdir=$PWD buck-test-restore-XXX)
name=''${dir##*/}

cleanup()
{
  rm -rf $dir
}
trap cleanup EXIT

mkdir -p $dir
${pkgs.rsync}/bin/rsync -rlt ops/buck-test/reexport/project/ $dir/
ln -s $dir $name

buck kill
buck build //$name/... -j12 -v 2,stderr
echo "" >> $name/M3.hs
buck build //$name/... -j12 -v 2,stderr
buck kill
''
