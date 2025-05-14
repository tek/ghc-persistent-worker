"""
FIXME: please write a docstring here describing what this module is for
"""

load("@prelude//genrule_toolchain.bzl", "GenruleToolchainInfo")

def nix_bash_genrule_toolchain_impl(_ctx: AnalysisContext) -> list[Provider]:
    return [
        DefaultInfo(),
        GenruleToolchainInfo(),
    ]

nix_bash_genrule_toolchain = rule(
    impl = nix_bash_genrule_toolchain_impl,
    attrs = {
        "bash": attrs.dep(
            providers = [RunInfo],
            default = "//:bash",
        ),
    },
    is_toolchain_rule = True,
)
