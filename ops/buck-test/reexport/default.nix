# Test that the make state is restored from the Buck cache when recompiling a changed module after that module had been
# built successfully previously, for the specific case of reexporting a class from an external dependency.
{...}: {
  build = ''
  buck build //$package/... -j12 -v 2,stderr
  echo "" >> $package/M3.hs
  buck build //$package/... -j12 -v 2,stderr
  '';
}
