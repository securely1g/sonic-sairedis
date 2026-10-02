# Bazel CI checks

These checks support the VS, Python 3, VPP-disabled build with swss-common's
default YANG configuration. The workflow is configured to run them in native
Trixie AMD64 and ARM64 containers. The Make workflows retain the wider
configuration matrix.

## Required targets

`required-targets.json` lists the canonical aggregate, seven tests that do not
require external services, and all 16 public package labels. The three
development debug labels alias runtime debug labels, producing 13 unique tar
outputs.

Keep required labels explicit. When a target changes, update the manifest and
workflow together, and preserve the existing test membership and execution
policy.

## Source ownership and reachability

`check_source_reachability.py` reads aquery JSON from standard input and writes
a concise JSON report before returning a failure. Run it from the repository
root:

```sh
bazel aquery --jobs=4 --lockfile_mode=error \
  --output=jsonproto --noinclude_artifacts --include_commandline \
  'mnemonic("CppCompile", deps(//:canonical_outputs))' \
  | python3 bazel/ci/check_source_reachability.py \
      --manifest bazel/ci/expected_no_vpp_sources.json \
      --output artifacts/validation/source-reachability.json
```

Use `set -o pipefail` when running that pipeline in an interactive shell so a
Bazel failure is preserved. Add `--config=aarch64` to the Bazel command in a
native Trixie ARM64 environment.

The source manifest contains 358 distinct source paths and 366 reviewed
target/source pairs. Each pair must occur once. This prevents a test compile
from hiding a missing production compile of the same source. Generated
metadata, SAI entry stubs, and the Python wrapper must come from their declared
Bazel output paths; SAI support sources must come from the pinned archive.
External dependency and execution-tool compilations receive no component
coverage credit.

The checker reports configuration identities for diagnosis. It does not prove
platform equivalence, compiler execution, or CodeQL extraction. The selected
source set was measured from the AMD64 Make reference; ARM64 still requires
native execution evidence.

The manifest guards the exact tracked `Makefile.am` path set, `configure.ac`,
and the `SAI` gitlink. It checks both Git index bytes and working-tree bytes.
There is no automatic refresh mode. When Make source inputs change:

1. Build and audit the matching Make profile to obtain its source inventory.
2. Review the Bazel owner of every source, including any deliberate library
   factoring used by an executable or test.
3. Update the source union, target/source pairs, generated-source mappings,
   reviewed pair identity, and Make input hashes together.

A new Bazel query supplies observed results; it does not supply the expected
source contract by itself.

## Package and debug verification

`verify_packages.py` consumes already built package outputs. It resolves one
tar per public label in the selected Bazel configuration and requires the
three alias mappings and 13 unique outputs in `required-targets.json`.
`package-contract.json` describes the component layout and ELF expectations.

The verifier checks:

- Exact non-directory paths, types, symlink targets, and metadata explicitly
  declared by the component package rules.
- ELF class, native machine, little-endian encoding, type, and SONAME for each
  packaged binary.
- Matching runtime/debug build IDs, nonempty file-backed debug sections, and
  debuglink filenames and CRCs for all 14 pairs.
- A GDB `info line sai_api_initialize` lookup using the paired libsairedis
  symbols, without executing the target.
- Label/output mapping, hashes, checked configuration, and dependency pins in
  the artifact provenance report. Resolve SAI, Common, and build-infra's actual
  canonical repositories, check their fetched module versions against the root
  declarations, and retain the selected immutable registry source hashes.
- Agreement between the SAI module's source provenance and the Make gitlink.

Inherited tar defaults and differences from the Make package inventory are
reported as observations. They are not silently rewritten as new component
requirements. The verifier reports scoped check success separately from Make
metadata parity and deployed runtime closure.

When package declarations intentionally change, review the contract against
the source declarations and the matching Make inventory. Preserve the
distinction between explicitly declared metadata and inherited defaults.
Do not populate expected values automatically from a newly produced archive.

Use a fresh artifact directory for each run. The verifier writes its validation
report before returning a failure. On success it copies only the 13 unique tar
outputs and their provenance into that directory. Use
`python3 bazel/ci/verify_packages.py --help` for the current command interface.
