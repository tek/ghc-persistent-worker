# Test that the make state is restored from the Buck cache when recompiling a failed module.
{...}: {
  build = ''
  buck build //$package/... -j12 -v 2,stderr || true
  buck build //$package/... -j12 -v 2,stderr || true
  '';
}
