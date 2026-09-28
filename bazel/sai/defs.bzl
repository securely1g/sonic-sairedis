"""Declared SAI metadata and sairedis API stub actions."""

load("//bazel/tools:defs.bzl", "PythonRuntimeInfo")

_PERL_TOOLCHAIN = "@rules_perl//perl:exec_toolchain_type"

def _source_manifest(ctx, files, marker, suffix):
    if not marker.path.endswith(suffix):
        fail("marker %s does not end with %s" % (marker.path, suffix))
    root = marker.path[:-len(suffix)]
    entries = []
    for source in files:
        if not source.path.startswith(root + "/"):
            fail("source %s is outside %s" % (source.path, root))
        entries.append({"source": source.path, "destination": source.path[len(root) + 1:]})
    manifest = ctx.actions.declare_file(ctx.label.name + ".inputs.json")
    ctx.actions.write(manifest, json.encode(entries))
    return manifest

def _sai_metadata_impl(ctx):
    python = ctx.attr._python[PythonRuntimeInfo]
    perl = ctx.toolchains[_PERL_TOOLCHAIN].perl_runtime
    manifest = _source_manifest(ctx, ctx.files.srcs, ctx.file.marker, "/meta/parse.pl")
    args = ctx.actions.args()
    args.add(ctx.file._generator)
    args.add("--manifest", manifest)
    args.add("--tool-bundle", ctx.file.tool_bundle.path)
    args.add("--perl", perl.interpreter)
    args.add_all(perl.perlopt, before_each = "--perl-option")
    args.add("--source-out", ctx.outputs.source)
    args.add("--header-out", ctx.outputs.header)
    args.add("--test-out", ctx.outputs.test_source)
    args.add("--swig-out", ctx.outputs.swig)
    ctx.actions.run(
        executable = python.interpreter,
        arguments = [args],
        inputs = ctx.files.srcs + [manifest],
        tools = depset(
            [python.interpreter, perl.interpreter, ctx.file._generator, ctx.file.tool_bundle],
            transitive = [python.files, perl.runtime],
        ),
        outputs = [ctx.outputs.source, ctx.outputs.header, ctx.outputs.test_source, ctx.outputs.swig],
        env = {"LANG": "C", "LC_ALL": "C", "PYTHONHASHSEED": "0"},
        mnemonic = "GenerateSaiMetadata",
        progress_message = "Generating SAI metadata",
    )
    return [DefaultInfo(files = depset([ctx.outputs.source, ctx.outputs.header, ctx.outputs.test_source, ctx.outputs.swig]))]

sai_metadata = rule(
    implementation = _sai_metadata_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "marker": attr.label(allow_single_file = True, mandatory = True),
        "tool_bundle": attr.label(allow_single_file = True, cfg = "exec", mandatory = True),
        "source": attr.output(mandatory = True),
        "header": attr.output(mandatory = True),
        "test_source": attr.output(mandatory = True),
        "swig": attr.output(mandatory = True),
        "_generator": attr.label(default = Label("//bazel/sai:generate_metadata.py"), allow_single_file = True, cfg = "exec"),
        "_python": attr.label(default = Label("//bazel/tools:python_runtime"), providers = [PythonRuntimeInfo], cfg = "exec"),
    },
    toolchains = [_PERL_TOOLCHAIN],
)

def _sai_stub_impl(ctx):
    python = ctx.attr._python[PythonRuntimeInfo]
    perl = ctx.toolchains[_PERL_TOOLCHAIN].perl_runtime
    manifest = _source_manifest(ctx, ctx.files.srcs, ctx.file.marker, "/inc/sai.h")
    args = ctx.actions.args()
    args.add(ctx.file._generator)
    args.add("--manifest", manifest)
    args.add("--perl", perl.interpreter)
    args.add_all(perl.perlopt, before_each = "--perl-option")
    args.add("--stub", ctx.file.stub)
    args.add("--class-name", ctx.attr.class_name)
    args.add("--namespace", ctx.attr.namespace)
    args.add("--out", ctx.outputs.out)
    ctx.actions.run(
        executable = python.interpreter,
        arguments = [args],
        inputs = ctx.files.srcs + [ctx.file.stub, manifest],
        tools = depset([python.interpreter, perl.interpreter, ctx.file._generator], transitive = [python.files, perl.runtime]),
        outputs = [ctx.outputs.out],
        env = {"LANG": "C", "LC_ALL": "C", "PYTHONHASHSEED": "0"},
        mnemonic = "GenerateSaiStub",
        progress_message = "Generating %{label}",
    )
    return [DefaultInfo(files = depset([ctx.outputs.out]))]

sai_stub = rule(
    implementation = _sai_stub_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "marker": attr.label(allow_single_file = True, mandatory = True),
        "stub": attr.label(allow_single_file = True, mandatory = True),
        "class_name": attr.string(mandatory = True),
        "namespace": attr.string(mandatory = True),
        "out": attr.output(mandatory = True),
        "_generator": attr.label(default = Label("//bazel/sai:generate_stub.py"), allow_single_file = True, cfg = "exec"),
        "_python": attr.label(default = Label("//bazel/tools:python_runtime"), providers = [PythonRuntimeInfo], cfg = "exec"),
    },
    toolchains = [_PERL_TOOLCHAIN],
)
