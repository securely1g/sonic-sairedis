# Shared infrastructure integration

Sairedis pins sonic-build-infra commit
`8851bb567ad8532f1e7d882fda8fab864d167c0c` from
[PR #2](https://github.com/securely1g/sonic-build-infra/pull/2) by archive URL
and integrity in `MODULE.bazel`. This commit adds the shared C++ system-header
correction to the
existing `83b4e9d963f7f268d06983a8c954fc5d6d93ce2b` infrastructure baseline.
The compiler uses the declared GCC and Trixie header inputs for C++ actions.
The archive has SHA256
`71c4fd85b493d5625b8a1d83f5788824f01c62f7054d0ab84455cbca0e5fb30a`.

Replace this archive pin with an immutable registry version when that version
contains the compiler correction. The optional runtime-path patch below remains
necessary until the selected infrastructure also provides its feature.

## Optional installed runtime paths

This patch is copied byte-for-byte from securely1g/sonic-swss-common PR #6 at
commit `e2d30c70a958acbb1ddc724c96fe971eaee1c856`:

https://github.com/securely1g/sonic-swss-common/blob/e2d30c70a958acbb1ddc724c96fe971eaee1c856/tools/bazel/yang/patches/sonic-build-infra-optional-runtime-paths.patch

SHA256: `23989d4d453f5272ea664e6b15a67b2cff86bf45a8c1640e50c7744d8d5c802f`

The patch adds the `sonic_installed_runtime_paths` toolchain feature to the
selected sonic-build-infra archive. The feature remains enabled for ordinary
target links and can be disabled by the private YANG execution binding so it
resolves native libraries from declared
Bazel runfiles. Sairedis applies the patch through its root
`archive_override` because Bazel ignores overrides declared by dependency
modules.

Remove this patch when sairedis selects shared
infrastructure with equivalent behavior: installed runtime paths enabled by
default and the same feature available for private execution tools to disable.
