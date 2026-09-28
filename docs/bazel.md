# Building sonic-sairedis with Bazel

This guide covers the native Trixie VS profile built with Bazel. The existing
Make build produces Debian packages and covers the broader SONiC build matrix.

## Build configuration

The Bazel profile uses Debian Trixie userspace, matching native execution and
target architectures, the virtual SAI backend, Python 3 bindings, VPP disabled,
and swss-common's default configuration with YANG enabled. The workflow defines
native AMD64 and ARM64 jobs for this profile.

Run Bazel inside the matching Trixie userspace. The target and host platform
flags in `.bazelrc` select the pinned toolchains and declare the execution
environment. The commands assume Bash and Git are available for the workspace
status script.

| Configuration | Bazel selection |
| --- | --- |
| Trixie AMD64, VS, Python 3, VPP disabled, YANG enabled | Default target and host platforms |
| Trixie ARM64, VS, Python 3, VPP disabled, YANG enabled | `--config=aarch64` in Trixie ARM64 userspace |

Bookworm, ARMHF, vendor SAI, RPC, DASH SAI, and VPP continue to use the existing
Make workflows. The Bazel graph records external dependency inputs for vendor
SAI, RPC, DASH SAI, and VPP; those configurations are outside the Bazel profile
described here.

The module pin selects swss-common commit
`e2d30c70a958acbb1ddc724c96fe971eaee1c856` from
[PR #6](https://github.com/securely1g/sonic-swss-common/pull/6). It generates
`cfg_schema.h` from declared YANG inputs, preserving the default feature set
used by the Make reference.

The infrastructure archive override selects sonic-build-infra commit
`8851bb567ad8532f1e7d882fda8fab864d167c0c` from
[PR #2](https://github.com/securely1g/sonic-build-infra/pull/2). Its shared GCC
correction applies the existing `-nostdinc` option to C++ compile actions so
they use the declared GCC and Trixie system headers. The root also retains
PR #6's optional runtime-path feature for the private YANG execution binding.
The archive and patch provenance and their removal conditions are recorded in
[third_party/sonic-build-infra](../third_party/sonic-build-infra/README.md).

The optional `--@sonic_swss_common//tools/bazel:yang_modules=False` setting
omits swss-common's decorator and default value provider implementations.
The commands below keep YANG enabled by omitting that override.

The repository pins Bazel 8.5.1 in `.bazelversion`. Use Bazelisk to select that
version. The module and registry pins in `MODULE.bazel` and `.bazelrc` provide
the compiler, sysroot, native dependencies, and build tools.

## Build the component

From the repository root inside Trixie AMD64 userspace:

```sh
bazel build --lockfile_mode=error //pyext:python3_files //syncd:syncd
```

These targets request the metadata, Redis, and VS shared libraries, the Python
3 extension and module files, and the VS sync daemon. Test execution is a
separate step.

Useful individual targets include:

| Target | Output |
| --- | --- |
| `//meta:saimetadata` | Metadata library with SONAME `libsaimetadata.so.0` |
| `//meta:saimeta` | Meta library with SONAME `libsaimeta.so.0` |
| `//lib:sairedis` | Redis library with SONAME `libsairedis.so.0` |
| `//vslib:libsaivs_shared` | VS library with SONAME `libsaivs.so.0` |
| `//pyext:pysairedis_py3` | Python 3 native extension |
| `//syncd:syncd` | VS sync daemon |

C++ consumers should use the corresponding `saimetadata_shared`,
`saimeta_shared`, `sairedis_shared`, or `saivs_shared` target. These targets
provide headers and dynamic linkage. The build keeps generated SAI entry
points separate from the C++ cores because the Redis, VS, and proxy backends
export the same SAI C function names.

Build the larger `//:canonical_outputs` target for the diagnostic and test
binaries from the Make graph with VPP disabled, including the TestDash sources.
The workflow requires this aggregate and checks its configured source ownership
against 358 reviewed component source paths and 366 target/source pairs.

## Tests without external services

Run the following seven existing tests without external services:

```sh
bazel test --lockfile_mode=error --nocache_test_results --test_output=errors \
  //lib:tests_test \
  //tests:tests_test \
  //saiasiccmp:tests \
  //unittest/meta:tests \
  //unittest/proxylib:tests \
  //unittest/saidump:tests \
  //unittest/saisdkdump:tests
```

The existing `//vslib:tests` executable requires Redis and is outside this
seven-test set. Run it in an isolated environment with a disposable Redis
instance. Coverage of its kernel network setup requires the corresponding
network capabilities and successful setup operations; the process exit alone
does not establish that coverage when setup reports errors. The existing Azure
workflow retains the wider service, capability, ASAN, and downstream VS tests.

## Runtime, development, and debug archives

The Bazel package targets produce tar archives for later image assembly. Debian
packages still use Make.

| Component | Runtime archive | Development archive | Detached symbols |
| --- | --- | --- | --- |
| Redis SAI | `//lib:libsairedis_pkg` | `//lib:libsairedis_dev_pkg` | `//lib:libsairedis_pkg.debug_symbols` |
| Metadata and meta | `//meta:libsaimetadata_pkg` | `//meta:libsaimetadata_dev_pkg` | `//meta:libsaimetadata_pkg.debug_symbols` |
| Virtual SAI | `//vslib:libsaivs_pkg` | `//vslib:libsaivs_dev_pkg` | `//vslib:libsaivs_pkg.debug_symbols` |
| Python 3 binding | `//pyext:pysairedis_pkg` | — | `//pyext:pysairedis_pkg.debug_symbols` |
| VS syncd and helpers | `//syncd:syncd_pkg` | — | `//syncd:syncd_pkg.debug_symbols` |

For example, build the Redis runtime, headers, and symbols with:

```sh
bazel build --lockfile_mode=error \
  //lib:libsairedis_pkg \
  //lib:libsairedis_dev_pkg \
  //lib:libsairedis_pkg.debug_symbols
```

Use `cquery` to find an artifact in the selected configuration:

```sh
bazel cquery --lockfile_mode=error --output=files //lib:libsairedis_pkg
bazel cquery --lockfile_mode=error --output=files //lib:libsairedis_pkg.debug_symbols
```

The three development `.debug_symbols` labels alias their component's runtime
symbol archive. The 16 public package labels therefore map to 13 unique tar
files.

Each package uses a shared transition that adds `--copt=-g`,
`--strip=never`, and a linker build ID to the linked ELF used for packaging.
The packaging actions derive both a stripped runtime copy and a detached symbol
file from that same ELF. Symbols are stored under
`usr/lib/debug/.build-id/<two digits>/<remaining digits>.debug`, and the runtime
file carries a matching `.gnu_debuglink`. These packaging flags do not change
the default flags of a separately requested raw library target.

The package verifier requires all 14 expected runtime/debug pairs to have
matching build IDs and debuglink CRCs, and requires GDB to load the detached
libsairedis symbols and resolve `sai_api_initialize` to a source line. To inspect
an extracted pair, configure GDB's debug directory before loading the runtime
file:

```text
(gdb) set debug-file-directory /path/to/staging/usr/lib/debug
(gdb) file /path/to/staging/usr/lib/x86_64-linux-gnu/libsairedis.so.0.0.0
(gdb) info line sai_api_initialize
```

The symbol archives do not bundle source files. Source listing requires the
matching checkout at the recorded path or an appropriate GDB source-path
mapping.

The verifier reports inherited archive metadata separately from explicit
component requirements. Known differences from Make include inherited `0755`
modes for detached symbol files and 123 metadata/VS API headers, which Make
installs as `0644`. It also reports the actual UID/GID on debug archive root
directory entries, whose ownership the component does not explicitly set. Use
the artifact report for the values produced by each run; complete Make metadata
parity requires separate validation.

## Runtime lookup

The standalone `.bazelrc` enables ELF `RUNPATH` so `LD_LIBRARY_PATH` can select
matching Bazel libraries during local execution. Consumer checks must verify
that the loaded sairedis component, swss-common, libyang, and libxxhash libraries
match the selected build inputs. The pinned toolchain still contributes absolute
runtime paths. Downstream Bazel roots use their own `.bazelrc`, so deployed
package lookup and downstream runtime closure require their own validation.

## Continuous integration

The Bazel workflow defines `Component (AMD64)` on `ubuntu-24.04` and
`Component (ARM64)` on `ubuntu-24.04-arm`, each inside a pinned Debian Trixie
container. Each job is configured to verify its native architecture, check
Bazel formatting, build `//:canonical_outputs`, run the seven tests listed
above, check configured source ownership against the reviewed Make inventory,
and build all 16 public package labels. The package verifier checks their 13
unique tar outputs and the 14 runtime/debug pairs. The workflow keeps the
default YANG setting and verifies that its selected value is enabled.

The source check requires 358 distinct component translation units and 366
reviewed target/source pairs. It reports configuration identities and excludes
external dependency actions from component coverage. Changes to Make source
declarations require a reviewed inventory update. This query checks configured
graph membership; it does not establish compiler tracing or CodeQL coverage.

The package verifier checks the declared component layout, ELF identity,
runtime/debug pairing, and GDB lookup. It reports inherited archive metadata
and differences from the Make reference separately. Its success does not claim
complete package metadata parity or deployed runtime closure.

When a run produces uploads, find them in the **Artifacts** section of its
Actions run page. In the names below, `<arch>` is `AMD64` or `ARM64`, and
`<workflow SHA>` is GitHub's `github.sha` value for that run.

| Artifact name | Contents | Upload behavior |
| --- | --- | --- |
| `sonic-sairedis-bazel-validation-<arch>-<workflow SHA>` | Available files from `artifacts/validation/`, including environment and validation reports | Attempted on every job outcome; no matching files produce a warning |
| `sonic-sairedis-bazel-trixie-<arch>-<workflow SHA>` | The 13 unique tar files from `artifacts/packages/` and `artifacts/provenance.json` | Runs after preceding steps succeed; no matching files are an error |

Use the job results and downloaded artifacts from the relevant Actions run to
confirm which required checks and outputs succeeded. The existing Azure and
CodeQL workflows continue to use Make.

## Build modes

The component flags mirror the corresponding `configure` choices:

| Flag | Effect |
| --- | --- |
| `--//:enable_debug` | Adds `-ggdb` and `DEBUG` |
| `--//:enable_coverage` | Adds the legacy coverage instrumentation and `NDEBUG` |
| `--//:enable_asan` | Applies the legacy syncd AddressSanitizer selection |

Debug and coverage are mutually exclusive, matching `configure.ac`. The ASAN
selection instruments the syncd executable sources and enables the syncd core
define, matching Make's instrumentation scope. These optional modes need
separate validation outside the default workflow profile.

## Generated SAI inputs

The Bazel build consumes an immutable SAI source archive matching the tracked
`SAI` gitlink. It declares metadata generation, the Redis/VS/proxy SAI entry
stubs, and the Python wrapper as build actions. Generated files stay in Bazel's
output tree.

The attribute version header is a pinned generated input with source and tag
provenance under `third_party/sai`. This preserves the version filtering data
that upstream `attrversion.sh` obtains from Git history. Update that input and
its provenance whenever the SAI pin changes.

## Debian packages

For the VS and Python 3 profile, use the existing Make packaging flow:

```sh
./autogen.sh
dpkg-buildpackage -us -uc -b -Psyncd,vs,nopython2 -j"$(nproc)"
```

The build environment controls optional dependency detection such as VPP.
Use the repository's documented SONiC build environment for the required
distribution and target architecture.
