"""Opt-in online verification of the Windows curl archives declared in aqua.

Run with the repository's PyYAML-enabled Python: python tests/curl-windows.py.
Both architectures are downloaded into memory; their binaries are not executed.
"""

import argparse
import hashlib
import io
from pathlib import Path
import re
import struct
from urllib.request import urlopen
from zipfile import ZipFile

import yaml


REPOSITORY = Path(__file__).resolve().parents[1]
EXPECTED_MACHINES = {"amd64": 0x8664, "arm64": 0xAA64}


def render_template(template, version, architecture):
    """Resolve the two aqua template fields used by the reviewed curl definition."""
    rendered = template.replace("{{.Version}}", version).replace(
        "{{.Arch}}", architecture
    )
    if "{{" in rendered:
        raise ValueError(f"Unsupported aqua template: {template}")
    return rendered


def download(url):
    """Fetch one declared HTTPS curl artifact with a bounded connection timeout."""
    if not url.startswith("https://curl.se/windows/"):
        raise ValueError(f"Unexpected curl artifact origin: {url}")
    with urlopen(url, timeout=60) as response:
        return response.read()


def verify_architecture(package, version, architecture):
    """Check the published checksum, configured ZIP member, and native PE machine."""
    if f"windows/{architecture}" not in package["supported_envs"]:
        raise ValueError(f"Architecture is not declared: {architecture}")
    archive_architecture = package["replacements"][architecture]
    archive_url = render_template(package["url"], version, archive_architecture)
    checksum = package["checksum"]
    if (
        checksum["type"] != "http"
        or checksum["algorithm"] != "sha256"
        or checksum["file_format"] != "regexp"
    ):
        raise ValueError("Unsupported curl checksum configuration")
    checksum_url = render_template(checksum["url"], version, archive_architecture)
    checksum_text = download(checksum_url).decode("utf-8")
    matches = list(re.finditer(checksum["pattern"]["checksum"], checksum_text))
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one configured checksum match: {checksum_url}")
    archive_bytes = download(archive_url)
    actual_digest = hashlib.sha256(archive_bytes).hexdigest()
    if actual_digest != matches[0].group(1).lower():
        raise ValueError(f"Archive SHA256 mismatch: {archive_url}")
    executable = next(file for file in package["files"] if file["name"] == "curl")
    member = render_template(executable["src"], version, archive_architecture)
    with ZipFile(io.BytesIO(archive_bytes)) as archive:
        executable_bytes = archive.read(member)
    if executable_bytes[:2] != b"MZ":
        raise ValueError(f"Missing DOS executable header: {member}")
    pe_offset = struct.unpack_from("<I", executable_bytes, 0x3C)[0]
    if executable_bytes[pe_offset:pe_offset + 4] != b"PE\0\0":
        raise ValueError(f"Missing PE signature: {member}")
    machine = struct.unpack_from("<H", executable_bytes, pe_offset + 4)[0]
    if machine != EXPECTED_MACHINES[architecture]:
        raise ValueError(f"Wrong PE machine for {architecture}: 0x{machine:04X}")
    print(
        f"PASS windows/{architecture} {version} SHA256={actual_digest} "
        f"PE=0x{machine:04X} member={member}"
    )


def main():
    """Verify selected official archives using the repository's current aqua pin."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--architecture", choices=("all", *EXPECTED_MACHINES), default="all"
    )
    arguments = parser.parse_args()
    configuration = yaml.safe_load((REPOSITORY / "aqua.yaml").read_text(encoding="utf-8"))
    registry = yaml.safe_load(
        (REPOSITORY / "aqua-registry.yaml").read_text(encoding="utf-8")
    )
    pin = next(
        package for package in configuration["packages"]
        if package["name"].startswith("curl/curl-for-win@")
    )
    if pin.get("registry") != "local":
        raise ValueError("Expected curl to use the local registry")
    package_name, version = pin["name"].split("@", 1)
    package = next(
        package for package in registry["packages"] if package.get("name") == package_name
    )
    architectures = (
        EXPECTED_MACHINES if arguments.architecture == "all" else [arguments.architecture]
    )
    for architecture in architectures:
        verify_architecture(package, version, architecture)


if __name__ == "__main__":
    main()
