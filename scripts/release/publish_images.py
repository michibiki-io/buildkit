"""Publish verified Docker archives under a single multi-platform image tag."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile


ARCHITECTURES = ("amd64", "arm64")


def sha256(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


def archive_image(archive_path, architecture):
    with tarfile.open(archive_path, "r:gz") as archive:
        with archive.extractfile("manifest.json") as manifest:
            (entry,) = json.load(manifest)
        (name,) = entry["RepoTags"]
        with archive.extractfile(entry["Config"]) as config_file:
            config = config_file.read()

    image = json.loads(config)
    if (image.get("os"), image.get("architecture")) != ("linux", architecture):
        raise ValueError(f"{archive_path.name} is not linux/{architecture}")
    return name, sha256(config)


def docker(*args, capture=False):
    result = subprocess.run(["docker", *args], check=True, stdout=subprocess.PIPE if capture else None)
    return result.stdout


def registry_manifest(reference):
    return docker("buildx", "imagetools", "inspect", "--raw", reference, capture=True)


def publish_platform(repository, version, architecture, archive_path, name, expected_config):
    docker("load", "--input", str(archive_path))

    reference = f"{repository}:{version}-{architecture}"
    docker("tag", name, reference)
    docker("push", "--platform", f"linux/{architecture}", reference)

    # The containerd store reports the image target digest as the local ID.
    # The registry manifest identifies the platform config in either store.
    manifest = registry_manifest(reference)
    actual_config = json.loads(manifest)["config"]["digest"]
    if actual_config != expected_config:
        raise ValueError(f"{reference} config is {actual_config}, expected {expected_config}")
    return sha256(manifest)


def publish(directory, repository, version, revision):
    archives = {arch: directory / f"buildkit-{arch}.tar.gz" for arch in ARCHITECTURES}
    images = {arch: archive_image(archive, arch) for arch, archive in archives.items()}
    platforms = {
        f"linux/{arch}": publish_platform(repository, version, arch, archives[arch], *images[arch])
        for arch in ARCHITECTURES
    }

    version_ref = f"{repository}:{version}"
    docker(
        "buildx", "imagetools", "create", "--tag", version_ref,
        *(f"{repository}@{digest}" for digest in platforms.values()),
    )
    index = registry_manifest(version_ref)
    descriptors = json.loads(index)["manifests"]
    actual = {
        f'{item["platform"]["os"]}/{item["platform"]["architecture"]}': item["digest"]
        for item in descriptors
    }
    if len(descriptors) != len(platforms) or actual != platforms:
        raise ValueError(f"Unexpected platform manifests in {version_ref}: {actual}")

    digest = sha256(index)
    reference = f"{repository}@{digest}"
    record = {
        "schema_version": 1,
        "images": {
            "buildkit": {
                "image": repository,
                "tag": version,
                "tag_reference": version_ref,
                "digest": digest,
                "reference": reference,
                "source_revision": revision,
                "platforms": platforms,
            }
        },
    }
    # BuildKit is the sole published image and every release includes it.
    contents = json.dumps(record, indent=2) + "\n"
    for filename in ("release-images.json", "approved-runtime-images.json"):
        (directory / filename).write_text(contents, encoding="utf-8")
    print(f"Verified {version_ref} at {reference}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("repository")
    parser.add_argument("version")
    parser.add_argument("revision")
    args = parser.parse_args()
    publish(args.directory, args.repository, args.version, args.revision)
