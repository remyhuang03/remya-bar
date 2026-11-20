"""Vendor the current Meteocons npm next release for offline use."""

import base64
import hashlib
import io
import json
import re
import tarfile
from pathlib import Path
from urllib.request import urlopen


ASSETS = Path(__file__).resolve().parents[1] / "assets/icons/weather"
REGISTRY = "https://registry.npmjs.org"
CONDITIONS = (
    "clear-day",
    "clear-night",
    "fog",
    "overcast",
    "partly-cloudy-day",
    "partly-cloudy-night",
    "rain",
    "snow",
    "thunderstorms-rain",
)


def download(url):
    with urlopen(url, timeout=30) as response:
        return response.read()


def package(name, files):
    metadata = json.loads(download(f"{REGISTRY}/@meteocons%2f{name}/next"))
    version = metadata["version"]
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+-[0-9A-Za-z.-]+", version):
        raise ValueError(f"Expected a Meteocons pre-release, got {version!r}")
    if metadata["license"] != "MIT":
        raise ValueError(f"Unexpected license in @meteocons/{name}@{version}")
    blob = download(f"{REGISTRY}/@meteocons/{name}/-/{name}-{version}.tgz")
    digest = base64.b64encode(hashlib.sha512(blob).digest()).decode()
    if metadata["dist"]["integrity"] != f"sha512-{digest}":
        raise ValueError(f"Integrity check failed for @meteocons/{name}@{version}")
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as archive:
        return version, {
            Path(file).name: archive.extractfile(f"package/{file}").read()
            for file in files
        }


def main():
    svg_version, svg = package(
        "svg-static",
        ["LICENSE", *(f"fill/{name}.svg" for name in (*CONDITIONS, "not-available"))],
    )
    lottie_version, lottie = package(
        "lottie",
        ["LICENSE", *(f"fill/{name}.json" for name in CONDITIONS)],
    )
    if svg_version != lottie_version:
        raise ValueError(f"Meteocons next versions differ: {svg_version}, {lottie_version}")
    if svg["LICENSE"] != lottie["LICENSE"]:
        raise ValueError("Meteocons packages have different license notices")

    for filename, data in (svg | lottie).items():
        (ASSETS / filename).write_bytes(data)
    (ASSETS / "VERSION").write_text(f"{svg_version}\n", encoding="utf-8")
    print(f"Meteocons {svg_version}")


if __name__ == "__main__":
    main()
