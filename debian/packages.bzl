"""Keep sairedis's existing Debian package boundaries and metadata."""

load("@sonic_build_infra//deb:metadata.bzl", "debian_metadata")
load("@sonic_build_infra//deb:sonic_deb.bzl", "sonic_deb")
load("@sonic_build_infra//deb:validation.bzl", "validate_debian_package")

_TOOLS = "@sonic_build_infra//tools/build_tools:"

def sairedis_debian_package(name, package_name, runtime, dependencies, init = False):
    """Apply the source .install manifest before computing package metadata."""
    controls = ["shlibs", "triggers"]
    if init:
        controls += ["conffiles", "preinst", "postinst", "prerm", "postrm"]
    native.genrule(
        name = name + "_stage",
        srcs = [runtime, "//debian:source_metadata", "//debian:control"] + (["//syncd:script_files"] if init else []),
        outs = [name + "/" + filename for filename in ["data.tar", "substvars", "stage.json"] + controls],
        tools = [":stage", _TOOLS + "dh_install", _TOOLS + "dh_fixperms", _TOOLS + "dh_installdeb"] + [_TOOLS + "dh_makeshlibs"] + ([_TOOLS + "dh_installinit"] if init else []),
        toolchains = ["@bsd_tar_toolchains//:resolved_toolchain"],
        cmd = select({
            "@platforms//cpu:x86_64": "arch=amd64\n",
            "@platforms//cpu:aarch64": "arch=arm64\n",
        }) + """
set -eu
$(execpath :stage) --data $(location {runtime}) \\
  --source "$$(dirname $(location //debian:control))" \\
  --package {package_name} --architecture "$$arch" \\
  --tar "$(BSDTAR_BIN)" \\
  --install $(execpath {tools}dh_install) \\
  --fixperms $(execpath {tools}dh_fixperms) \\
  --installdeb $(execpath {tools}dh_installdeb) \\
  --output-data $(location {name}/data.tar) \\
  --output-substvars $(location {name}/substvars) \\
  --receipt $(location {name}/stage.json) {extra}
""".format(
            name = name,
            runtime = runtime,
            package_name = package_name,
            tools = _TOOLS,
            extra = ("--makeshlibs $(execpath " + _TOOLS + "dh_makeshlibs) ") + ("--installinit $(execpath " + _TOOLS + "dh_installinit) --scripts $(locations //syncd:script_files) " if init else "") + " ".join(["--control-output %s=$(location %s/%s)" % (filename, name, filename) for filename in controls]),
        ),
    )
    debian_metadata(
        name = name + "_metadata",
        data = ":" + name + "/data.tar",
        control = "control",
        changelog = "changelog",
        package = package_name,
        dependencies = dependencies,
        substvars = ":" + name + "/substvars",
        substitutions = {} if init else {"misc:Pre-Depends": ""},
        generate_symbols = True,
    )
    control_files = {":" + name + "/" + filename: filename for filename in controls}
    native.filegroup(name = name + "_symbols", srcs = [":" + name + "_metadata"], output_group = "symbols")
    control_files[":" + name + "_symbols"] = "symbols"
    sonic_deb(
        name = name + "_deb",
        package = package_name,
        version = "1.0.0",
        data = ":" + name + "/data.tar",
        control_file = ":" + name + "_metadata",
        control_files = control_files,
        tags = ["manual"],
    )
    validate_debian_package(
        name = name + "_check",
        package = package_name,
        version = "1.0.0",
        deb = ":" + name + "_deb",
        data = ":" + name + "/data.tar",
        control = ":" + name + "_metadata",
        control_files = control_files,
        tags = ["manual"],
    )
