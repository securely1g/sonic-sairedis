"""Execution-configuration runtimes for the SAI generators."""

PythonRuntimeInfo = provider(
    "Declared Python interpreter and runtime files for execution tools.",
    fields = ["interpreter", "files"],
)

def _python_runtime_impl(ctx):
    runtime = ctx.toolchains["@rules_python//python:toolchain_type"].py3_runtime
    if runtime == None or runtime.interpreter == None:
        fail("SAI generators require a declared Python 3 interpreter")
    return [
        PythonRuntimeInfo(interpreter = runtime.interpreter, files = runtime.files),
        DefaultInfo(files = runtime.files),
    ]

python_runtime = rule(
    implementation = _python_runtime_impl,
    toolchains = ["@rules_python//python:toolchain_type"],
)

def _deb_tool_bundle_impl(ctx):
    python = ctx.attr._python[PythonRuntimeInfo]
    output = ctx.actions.declare_directory(ctx.label.name)
    args = ctx.actions.args()
    args.add(ctx.file._prepare)
    args.add("--out", output.path)
    args.add("--architecture", ctx.attr.architecture)
    args.add_all(ctx.files.debs, before_each = "--deb")
    ctx.actions.run(
        executable = python.interpreter,
        arguments = [args],
        inputs = ctx.files.debs,
        tools = depset([python.interpreter, ctx.file._prepare], transitive = [python.files]),
        outputs = [output],
        env = {"LANG": "C", "LC_ALL": "C", "PYTHONHASHSEED": "0"},
        mnemonic = "PrepareSaiGeneratorTools",
        progress_message = "Preparing declared SAI generator tools",
    )
    return [DefaultInfo(files = depset([output]))]

deb_tool_bundle = rule(
    implementation = _deb_tool_bundle_impl,
    attrs = {
        "architecture": attr.string(mandatory = True, values = ["amd64", "arm64"]),
        "debs": attr.label_list(allow_files = [".deb"], mandatory = True),
        "_prepare": attr.label(default = Label("//bazel/tools:prepare_deb_tools.py"), allow_single_file = True, cfg = "exec"),
        "_python": attr.label(default = Label("//bazel/tools:python_runtime"), providers = [PythonRuntimeInfo], cfg = "exec"),
    },
)
