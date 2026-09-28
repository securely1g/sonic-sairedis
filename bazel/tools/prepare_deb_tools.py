"""Prepare SAI generator tools from locked Debian archives without host utilities."""

from __future__ import annotations

import argparse
import gzip
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile


def ar_members(path: Path):
    with path.open("rb") as archive:
        if archive.read(8) != b"!<arch>\n":
            raise ValueError(f"{path} is not an ar archive")
        while header := archive.read(60):
            if len(header) != 60 or header[58:] != b"`\n":
                raise ValueError(f"invalid ar member in {path}")
            name = header[:16].decode("ascii").strip().rstrip("/")
            size = int(header[48:58])
            payload = archive.read(size)
            if len(payload) != size:
                raise ValueError(f"truncated ar member in {path}")
            if size % 2:
                archive.read(1)
            yield name, payload


def safe_path(root: Path, name: str) -> Path:
    relative = PurePosixPath(name.removeprefix("./"))
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"invalid archive path: {name}")
    target = root.joinpath(*relative.parts)
    if not target.parent.resolve().is_relative_to(root):
        raise ValueError(f"archive path escapes output: {name}")
    return target


def extract_payload(root: Path, payload: bytes) -> None:
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r:*") as archive:
        hardlinks = []
        for member in archive:
            if member.name in (".", "./"):
                continue
            target = safe_path(root, member.name)
            target.parent.mkdir(parents=True, exist_ok=True)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            if target.is_symlink() or target.is_file():
                target.unlink()
            if member.issym():
                link = member.linkname
                if link.startswith("/"):
                    link = os.path.relpath(root / link.lstrip("/"), target.parent)
                target.symlink_to(link)
            elif member.islnk():
                hardlinks.append((target, member.linkname))
            elif member.isfile():
                source = archive.extractfile(member)
                if source is None:
                    raise ValueError(f"missing archive data: {member.name}")
                with source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)
                target.chmod(member.mode & 0o777)
                os.utime(target, (0, 0))
        for target, name in hardlinks:
            source = safe_path(root, name)
            if not source.is_file():
                raise ValueError(f"missing hardlink target: {name}")
            os.link(source, target)


def loader_path(root: Path, architecture: str) -> Path:
    names = {
        "amd64": ("x86_64-linux-gnu", "ld-linux-x86-64.so.2"),
        "arm64": ("aarch64-linux-gnu", "ld-linux-aarch64.so.1"),
    }
    triplet, loader = names[architecture]
    candidates = [
        root / "usr/lib" / triplet / loader,
        root / "lib" / triplet / loader,
        root / "usr/lib64" / loader,
        root / "lib64" / loader,
        root / "lib" / loader,
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise RuntimeError(f"locked {architecture} packages contain no dynamic loader")


def library_directories(root: Path) -> list[Path]:
    directories = set()
    for path in root.rglob("*.so*"):
        if path.is_file():
            directories.add(path.parent)
    return sorted(directories)


def run_tool(command: list[str], *, environment: dict[str, str], data: bytes | None = None) -> bytes:
    result = subprocess.run(command, input=data, env=environment, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"tool exited {result.returncode}: {command}\n{result.stderr.decode(errors='replace')}")
    return result.stdout


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--architecture", choices=("amd64", "arm64"), required=True)
    parser.add_argument("--deb", action="append", default=[])
    args = parser.parse_args()
    root = Path(args.out).resolve()
    root.mkdir(parents=True, exist_ok=True)
    for deb in sorted(map(Path, args.deb)):
        payloads = [(name, payload) for name, payload in ar_members(deb) if name.startswith("data.tar")]
        if len(payloads) != 1:
            raise ValueError(f"expected one data payload in {deb}")
        extract_payload(root, payloads[0][1])

    loader = loader_path(root, args.architecture)
    libraries = library_directories(root)
    prefix = [str(loader), "--library-path", os.pathsep.join(map(str, libraries))]
    tools = {name: root / path for name, path in {
        "aspell": "usr/bin/aspell",
        "doxygen": "usr/bin/doxygen",
        "prezip_bin": "usr/bin/prezip-bin",
    }.items()}
    filter_candidates = sorted(root.rglob("nroff.amf"))
    if len(filter_candidates) != 1:
        raise RuntimeError("locked packages must contain one Aspell filter directory")
    filter_dir = filter_candidates[0].parent
    environment = {"LANG": "C", "LC_ALL": "C", "PATH": "", "HOME": str(root / ".home")}
    (root / ".home").mkdir()
    runtime_files = list(tools.items()) + [(path.name, path) for path in sorted(filter_dir.glob("*.so"))]
    for name, binary in runtime_files:
        if not binary.is_file():
            raise RuntimeError(f"locked packages contain no {name}: {binary}")
        listing = run_tool(prefix + ["--list", str(binary)], environment=environment).decode()
        if "not found" in listing:
            raise RuntimeError(f"incomplete runtime for {name}:\n{listing}")
        for resolved in re.findall(r"=>\s+(/\S+)", listing):
            if not Path(resolved).resolve().is_relative_to(root):
                raise RuntimeError(f"{name} resolved an undeclared library: {resolved}")

    data_candidates = sorted(root.rglob("en.dat"))
    if not data_candidates:
        raise RuntimeError("locked packages contain no Aspell English language data")
    data_dir = data_candidates[0].parent
    dictionary_dir = data_dir
    aspell = prefix + [str(tools["aspell"]), "--lang=en", f"--data-dir={data_dir}", f"--dict-dir={dictionary_dir}", f"--add-filter-path={filter_dir}"]
    # Debian compiles compressed word lists in postinst. Reproduce that work
    # here using only the locked prezip-bin and Aspell executables.
    for wordlist in sorted(root.rglob("*.cwl.gz")):
        compressed = gzip.decompress(wordlist.read_bytes())
        words = run_tool(prefix + [str(tools["prezip_bin"]), "-d"], environment=environment, data=compressed)
        output = dictionary_dir / wordlist.name.removesuffix(".cwl.gz")
        output = output.with_name(output.name + ".rws")
        run_tool(aspell + ["--encoding=utf-8", "create", "master", str(output)], environment=environment, data=words)
        os.utime(output, (0, 0))

    run_tool(aspell + ["list"], environment=environment, data=b"switch\n")
    versions = {
        "doxygen": run_tool(prefix + [str(tools["doxygen"]), "-v"], environment=environment).decode().strip(),
        "aspell": run_tool(prefix + [str(tools["aspell"]), "--version"], environment=environment).decode().strip(),
    }
    shutil.rmtree(root / ".home")
    manifest = {
        "format_version": 1,
        "architecture": args.architecture,
        "loader": str(loader.relative_to(root)),
        "library_directories": [str(path.relative_to(root)) for path in libraries],
        "tools": {name: str(path.relative_to(root)) for name, path in tools.items()},
        "aspell_data_directory": str(data_dir.relative_to(root)),
        "aspell_dictionary_directory": str(dictionary_dir.relative_to(root)),
        "aspell_filter_directory": str(filter_dir.relative_to(root)),
        "versions": versions,
    }
    (root / "toolchain.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
