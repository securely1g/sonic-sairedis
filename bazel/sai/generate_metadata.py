"""Run the SAI metadata generators with declared inputs and execution tools."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def main() -> None:
    parser = argparse.ArgumentParser()
    for name in ("manifest", "tool-bundle", "perl", "source-out", "header-out", "test-out", "swig-out"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--perl-option", action="append", default=[])
    args = parser.parse_args()
    inputs = json.loads(Path(args.manifest).read_text())
    sources = [(Path(entry["source"]).resolve(), entry["destination"]) for entry in inputs]
    bundle = Path(args.tool_bundle).resolve()
    toolchain = json.loads((bundle / "toolchain.json").read_text())
    if toolchain.get("format_version") != 1:
        raise RuntimeError("unsupported SAI generator tool bundle")
    loader = str(bundle / toolchain["loader"])
    libraries = os.pathsep.join(str(bundle / path) for path in toolchain["library_directories"])
    loader_command = [loader, "--library-path", libraries]
    doxygen = loader_command + [str(bundle / toolchain["tools"]["doxygen"])]
    perl = str(Path(args.perl).resolve())
    outputs = {
        "saimetadata.c": Path(args.source_out).resolve(),
        "saimetadata.h": Path(args.header_out).resolve(),
        "saimetadatatest.c": Path(args.test_out).resolve(),
        "saiswig.i": Path(args.swig_out).resolve(),
    }
    with tempfile.TemporaryDirectory(prefix="sai-metadata-") as temporary:
        root = Path(temporary) / "SAI"
        for directory in ("inc", "experimental", "custom", "meta"):
            (root / directory).mkdir(parents=True, exist_ok=True)
        for source, destination in sources:
            target = root / destination
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        meta = root / "meta"
        home = Path(temporary) / "home"
        home.mkdir()
        environment = {
            "HOME": str(home),
            "LANG": "C",
            "LC_ALL": "C",
            "PATH": "",
            "SAI_ASPELL": str(bundle / toolchain["tools"]["aspell"]),
            "SAI_ASPELL_LOADER": loader,
            "SAI_ASPELL_LIBRARY_PATH": libraries,
            "SAI_ASPELL_DATA_DIR": str(bundle / toolchain["aspell_data_directory"]),
            "SAI_ASPELL_DICT_DIR": str(bundle / toolchain["aspell_dictionary_directory"]),
            "SAI_ASPELL_FILTER_DIR": str(bundle / toolchain["aspell_filter_directory"]),
            "TMPDIR": temporary,
        }
        version_result = subprocess.run(doxygen + ["-v"], check=True, capture_output=True, text=True, env=environment)
        match = re.search(r"(\d+)\.(\d+)\.(\d+)", version_result.stdout)
        if not match:
            raise RuntimeError("could not parse declared doxygen version: " + version_result.stdout)
        config = "Doxyfile" if tuple(map(int, match.groups())) >= (1, 8, 16) else "Doxyfile.compat"
        result = subprocess.run(doxygen + [config], cwd=meta, capture_output=True, text=True, env=environment)
        doxygen_output = result.stdout + result.stderr
        if result.returncode or "warning" in doxygen_output.lower():
            raise RuntimeError("doxygen failed or emitted a warning:\n" + doxygen_output)
        subprocess.run([perl, *args.perl_option, "-I.", "parse.pl"], cwd=meta, check=True, env=environment)
        for filename, output in outputs.items():
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(meta / filename, output)


if __name__ == "__main__":
    main()
