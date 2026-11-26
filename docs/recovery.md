# Recovery

Restoring application data from the k8up backups into a separate namespace, next to the running application. The examples restore Vaultwarden.

## Backups

k8up writes to the restic repository `rest:http://10.0.0.8:8000/k3s/`. Every application namespace has a Secret `backup-repo` with the repository password (`repo-password`) and the REST server credentials (`rest-user`, `rest-password`).

Each run creates one snapshot per volume, with the path `/data/<pvc>`, and one per database dump, with the path `/<namespace>-<container>.sql`. The snapshot host is the namespace.

## 1. Prepare a namespace

```sh
kubectl create namespace restore-drill
kubectl -n vaultwarden get secret backup-repo -o json \
  | jq '{apiVersion, kind, type, data, metadata: {name: .metadata.name, namespace: "restore-drill"}}' \
  | kubectl create -f -
```

## 2. List the snapshots

k8up does not create Snapshot objects (`skipSnapshotSync`). List the snapshots with restic from a pod that uses the installed k8up image:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restic
  namespace: restore-drill
spec:
  restartPolicy: Never
  containers:
    - name: restic
      image: ghcr.io/k8up-io/k8up:v2.16.1
      command: ["sh", "-c", "sleep 3600"]
      env:
        - name: RESTIC_REPOSITORY
          value: rest:http://10.0.0.8:8000/k3s/
        - name: RESTIC_PASSWORD
          valueFrom: {secretKeyRef: {name: backup-repo, key: repo-password}}
        - name: RESTIC_REST_USERNAME
          valueFrom: {secretKeyRef: {name: backup-repo, key: rest-user}}
        - name: RESTIC_REST_PASSWORD
          valueFrom: {secretKeyRef: {name: backup-repo, key: rest-password}}
        - name: RESTIC_CACHE_DIR
          value: /tmp/restic-cache
```

```sh
kubectl -n restore-drill exec restic -- restic snapshots --no-lock --host vaultwarden
```

## 3. Restore the volume and the dump

One Restore per snapshot, each into a new PVC. The files land at the root of the PVC. `podSecurityContext` must match the application's user, as in its Schedule. `passwordSecretReg` is the field's name in the k8up API.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: vw-data
  namespace: restore-drill
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
---
apiVersion: k8up.io/v1
kind: Restore
metadata:
  name: vw-data
  namespace: restore-drill
spec:
  snapshot: <snapshot of /data/vaultwarden-data>
  podSecurityContext:
    runAsUser: 1000
    runAsGroup: 1000
  restoreMethod:
    folder:
      claimName: vw-data
  backend:
    repoPasswordSecretRef: {name: backup-repo, key: repo-password}
    rest:
      url: http://10.0.0.8:8000/k3s/
      userSecretRef: {name: backup-repo, key: rest-user}
      passwordSecretReg: {name: backup-repo, key: rest-password}
```

The dump is restored the same way into a second PVC, `vw-dump`, from the snapshot of `/vaultwarden-pgdump.sql`. Use `local-path` for these volumes; the `longhorn` storage class keeps volumes after they are deleted.

## 4. Load the dump

Create an empty database with the same image as the application's cluster. Do not copy the application's database Secret: the new cluster creates its own, `vw-drill-db-app`.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: vw-drill-db
  namespace: restore-drill
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:18.7-minimal-trixie
  bootstrap:
    initdb:
      database: vaultwarden
      owner: vaultwarden
  storage:
    storageClass: local-path
    size: 2Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: loader
  namespace: restore-drill
spec:
  restartPolicy: Never
  securityContext: {runAsUser: 1000, runAsGroup: 1000}
  containers:
    - name: psql
      image: ghcr.io/cloudnative-pg/postgresql:18.7-minimal-trixie
      command: ["sleep", "3600"]
      env:
        - {name: PGHOST, value: vw-drill-db-rw}
        - {name: PGDATABASE, value: vaultwarden}
        - name: PGUSER
          valueFrom: {secretKeyRef: {name: vw-drill-db-app, key: username}}
        - name: PGPASSWORD
          valueFrom: {secretKeyRef: {name: vw-drill-db-app, key: password}}
      volumeMounts:
        - {name: dump, mountPath: /dump}
  volumes:
    - {name: dump, persistentVolumeClaim: {claimName: vw-dump}}
```

The dumps are taken with `pg_dump --clean --if-exists`, so loading one drops and recreates every table in the target database. Check that the dump is complete, then load it:

```sh
kubectl -n restore-drill exec loader -- grep -c -- '-- PostgreSQL database dump complete' /dump/vaultwarden-pgdump.sql
kubectl -n restore-drill exec loader -- psql -X -v ON_ERROR_STOP=1 -q -f /dump/vaultwarden-pgdump.sql
```

The first command must print `1`. A truncated dump is still reported as a successful backup.

## 5. Check

- Compare row counts per table with the live database, read from its replica:

  ```sql
  select table_name, (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text
  from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE' order by 1;
  ```

- Compare file hashes of the restored volume with the live one: `find . -type f -exec sha256sum {} +`.
- Start the application with the restored volume and database, without a Service or HTTPRoute, and open it with `kubectl port-forward`.

## 6. Clean up

```sh
kubectl delete namespace restore-drill
```

The `local-path` volumes are deleted with the namespace.

## Not tested

- Restoring in place, over the running application.
- Restoring Gitea, Paperless, integrac, Immich and the media applications since their move to PostgreSQL or Longhorn.
- Restoring from the offsite copy.

## Restore tests

| Date | Application | Result |
|---|---|---|
| 2026-11-11 | Kavita | Volume restored into a new PVC; library and reading progress present |
| 2026-11-14 | Nextcloud | Files and `pg_dump` restored; 314 of 314 files identical, 137 of 138 tables equal (`oc_job_runs` had grown) |
| 2026-11-26 | Vaultwarden | Volume and `pg_dump` restored into `restore-drill`; 29 of 29 tables with identical row counts, 30 of 30 files identical, application started |
