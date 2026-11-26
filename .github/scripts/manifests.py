#!/usr/bin/env python3
"""Render every Argo CD application the way Argo CD does and validate the result with kubeconform."""

import argparse
import collections
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

import yaml

KUBE_VERSION = "1.37.2"
CRD_CATALOG = "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
SKIP = {
    "coredns": "a partial Deployment that Argo CD applies with server-side apply",
}


def run(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"failed: {' '.join(cmd)}\n{result.stderr}")
    return result.stdout


def kustomize(path):
    if shutil.which("kustomize"):
        return run(["kustomize", "build", path])
    return run(["kubectl", "kustomize", path])


def render_helm(name, namespace, source, workdir):
    helm = source.get("helm", {})
    cmd = [
        "helm", "template", helm.get("releaseName", name), source["chart"],
        "--repo", source["repoURL"],
        "--version", str(source["targetRevision"]),
        "--namespace", namespace,
        "--kube-version", KUBE_VERSION,
        "--include-crds",
    ]
    for values_file in helm.get("valueFiles", []):
        cmd += ["--values", values_file.removeprefix("$values/")]
    inline = helm.get("valuesObject") or (yaml.safe_load(helm["values"]) if helm.get("values") else None)
    if inline:
        inline_file = pathlib.Path(workdir, f"{name}-values.yaml")
        inline_file.write_text(yaml.safe_dump(inline))
        cmd += ["--values", str(inline_file)]
    return run(cmd)


def render_path(source):
    path = pathlib.Path(source["path"])
    if (path / "kustomization.yaml").exists():
        return kustomize(str(path))
    files = sorted(p for p in path.iterdir() if p.suffix in (".yaml", ".yml", ".json"))
    return "\n---\n".join(p.read_text() for p in files)


def render(out):
    out.mkdir(parents=True, exist_ok=True)
    shutil.copy("kubernetes/root.yaml", out / "root.yaml")
    with tempfile.TemporaryDirectory() as workdir:
        for variable in ("HELM_CONFIG_HOME", "HELM_CACHE_HOME", "HELM_DATA_HOME"):
            os.environ[variable] = os.path.join(workdir, variable.lower())
        for app_file in sorted(pathlib.Path("kubernetes/apps").glob("*.yaml")):
            shutil.copy(app_file, out / f"application-{app_file.name}")
            app = yaml.safe_load(app_file.read_text())
            name = app["metadata"]["name"]
            if name in SKIP:
                print(f"skipped {name}: {SKIP[name]}")
                continue
            spec = app["spec"]
            namespace = spec["destination"].get("namespace", "default")
            documents = []
            for source in spec.get("sources") or [spec["source"]]:
                if "chart" in source:
                    documents.append(render_helm(name, namespace, source, workdir))
                elif "path" in source:
                    documents.append(render_path(source))
            (out / f"{name}.yaml").write_text("\n---\n".join(documents))
            print(f"rendered {name}")


def validate(out):
    result = subprocess.run(
        [
            "kubeconform", "-output", "json", "-verbose", "-ignore-missing-schemas",
            "-kubernetes-version", KUBE_VERSION,
            "-schema-location", "default", "-schema-location", CRD_CATALOG,
            str(out),
        ],
        capture_output=True, text=True,
    )
    report = json.loads(result.stdout)
    by_status = collections.defaultdict(list)
    for resource in report["resources"]:
        by_status[resource["status"]].append(resource)
    skipped = collections.Counter(f"{r['kind']} ({r['version']})" for r in by_status["statusSkipped"])
    print(f"\nvalid: {len(by_status['statusValid'])}, skipped: {sum(skipped.values())}, "
          f"invalid: {len(by_status['statusInvalid'])}, errors: {len(by_status['statusError'])}")
    if skipped:
        print("kinds without a schema:")
        for kind, count in sorted(skipped.items()):
            print(f"  {kind}: {count}")
    failed = by_status["statusInvalid"] + by_status["statusError"]
    for resource in failed:
        print(f"{resource['filename']}: {resource['kind']} {resource['name']}: {resource['msg']}")
    return not failed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="rendered", type=pathlib.Path)
    parser.add_argument("--render-only", action="store_true")
    args = parser.parse_args()
    render(args.out)
    if not args.render_only and not validate(args.out):
        sys.exit(1)


if __name__ == "__main__":
    os.chdir(pathlib.Path(__file__).resolve().parents[2])
    main()
