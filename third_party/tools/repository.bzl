"""Original Debian archives used by the component-owned generator tools."""

def _generator_tools_repository_impl(ctx):
    manifest = json.decode(ctx.read(ctx.attr.manifest))
    if manifest.get("format_version") != 1:
        fail("unsupported generator tool manifest format")
    architecture = manifest["architectures"].get(ctx.attr.architecture)
    if architecture == None:
        fail("no generator tools locked for %s" % ctx.attr.architecture)

    downloads = []
    files = []
    for package in architecture["packages"]:
        output = "packages/" + package["filename"].split("/")[-1]
        files.append(output)
        downloads.append(ctx.download(
            url = package["urls"],
            output = output,
            sha256 = package["sha256"],
            block = False,
        ))
    for token in downloads:
        token.wait()

    ctx.file("BUILD.bazel", """\
package(default_visibility = ["//visibility:public"])
filegroup(name = "debs", srcs = %s)
exports_files(["SOURCE.lock.json"])
""" % repr(files))
    ctx.file("SOURCE.lock.json", json.encode_indent({
        "resolved_with": manifest["resolved_with"],
        "sources": manifest["sources"],
        "architecture": ctx.attr.architecture,
        "roots": architecture["roots"],
        "packages": architecture["packages"],
    }) + "\n")
    return ctx.repo_metadata(reproducible = True)

generator_tools_repository = repository_rule(
    implementation = _generator_tools_repository_impl,
    attrs = {
        "architecture": attr.string(mandatory = True, values = ["amd64", "arm64"]),
        "manifest": attr.label(allow_single_file = True, mandatory = True),
    },
)
