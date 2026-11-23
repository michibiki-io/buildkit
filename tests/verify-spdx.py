"""Verify that the exported OCI image has a digest-linked SPDX SBOM."""

import hashlib
import json
import sys
import tarfile


def verify(archive, architecture):
    members = {
        member.name.removeprefix("./"): member for member in archive if member.isfile()
    }

    def blob(digest):
        algorithm, value = digest.split(":", 1)
        with archive.extractfile(members[f"blobs/{algorithm}/{value}"]) as member:
            data = member.read()
        assert hashlib.new(algorithm, data).hexdigest() == value, digest
        return json.loads(data)

    with archive.extractfile(members["index.json"]) as member:
        manifests = json.load(member)["manifests"]
    (image,) = (
        descriptor
        for descriptor in manifests
        if descriptor.get("platform", {}).get("architecture") == architecture
    )
    subject = image["digest"]
    assert len(blob(subject)["layers"]) >= 3, "The fixture must export multiple layers"
    (attestation,) = (
        descriptor
        for descriptor in manifests
        if descriptor.get("annotations", {}).get("vnd.docker.reference.digest") == subject
    )
    statements = [blob(layer["digest"]) for layer in blob(attestation["digest"])["layers"]]
    (statement,) = (
        statement
        for statement in statements
        if statement.get("predicateType") == "https://spdx.dev/Document"
    )
    assert any(
        item["digest"].get("sha256") == subject.removeprefix("sha256:")
        for item in statement["subject"]
    ), "The SPDX statement must name the exported image"
    document = statement["predicate"]
    assert document["spdxVersion"].startswith("SPDX-"), document["spdxVersion"]
    assert any(
        package["name"] == "busybox" for package in document["packages"]
    ), "The scanner must read the Alpine root filesystem"
    print(f"PASS digest-linked SPDX for {architecture} {subject}")


if __name__ == "__main__":
    with tarfile.open(sys.argv[1]) as archive:
        verify(archive, sys.argv[2])
