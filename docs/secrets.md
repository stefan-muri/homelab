# Secrets

Every Kubernetes Secret is stored in Git as a SealedSecret, in a file `sealedsecret-<name>.yaml` next to the application. A SealedSecret is encrypted with the controller's public key. Only the controller in the cluster holds the private key and turns it back into a Secret. The plaintext values are kept in a password manager.

The commands use zsh syntax. `kubeseal` finds the controller in `kube-system` without extra flags.

## Create or replace a Secret

```sh
read -rs 'VALUE?Value: ' && echo
kubectl create secret generic NAME -n NAMESPACE --from-literal=KEY="$VALUE" --dry-run=client -o json \
  | kubeseal -o yaml > kubernetes/APP/sealedsecret-NAME.yaml
```

If the application uses a `kustomization.yaml`, add the file to its resources.

## Add or change a single key

```sh
read -rs 'VALUE?Value: ' && echo
kubectl create secret generic NAME -n NAMESPACE --from-literal=KEY="$VALUE" --dry-run=client -o json \
  | kubeseal --merge-into kubernetes/APP/sealedsecret-NAME.yaml
```

## Take over a Secret that already exists

The controller does not overwrite a Secret it did not create unless the Secret carries an annotation. Annotate it first, then seal it from the live values:

```sh
kubectl -n NAMESPACE annotate secret NAME sealedsecrets.bitnami.com/managed=true
kubectl -n NAMESPACE get secret NAME -o json \
  | jq '{apiVersion, kind, type, data, metadata: {name: .metadata.name, namespace: .metadata.namespace}}' \
  | kubeseal -o yaml > kubernetes/APP/sealedsecret-NAME.yaml
```

## Decrypt without the cluster

With the backed-up key, any SealedSecret in this repository can be decrypted offline:

```sh
kubeseal --recovery-unseal --recovery-private-key sealed-secrets-key.json < kubernetes/APP/sealedsecret-NAME.yaml
```

## Key backup

The controller's key is stored as a file attachment in the password manager. Export it:

```sh
kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o json \
  | jq '{apiVersion: "v1", kind: "List", items: [.items[] | {apiVersion, kind, type, data, metadata: {name: .metadata.name, namespace: .metadata.namespace, labels: .metadata.labels}}]}' \
  > sealed-secrets-key.json
```

The export keeps only the key pair, its name and namespace, and the label the controller looks for at startup.

Verify a downloaded copy of the backup. The test value is sealed with the cluster's public key and decrypted with the file alone. It prints `ok`:

```sh
kubectl create secret generic backup-test -n default --from-literal=check=ok --dry-run=client -o json \
  | kubeseal -o yaml \
  | kubeseal --recovery-unseal --recovery-private-key sealed-secrets-key.json \
  | jq -r '.data.check' | base64 -d; echo
```

Delete local copies of the key after use. Restoring the key is step 4 of [rebuild.md](rebuild.md).

## Design

- Key renewal is disabled (`keyrenewperiod: "0"`). A renewed key would not be in the backup, and new SealedSecrets would be encrypted with it.
- The `sealed-secrets` Application has no deletion finalizer. Deleting the Application must not delete the CRD, because that would delete every SealedSecret and the Secrets they own.
- The controller runs in `kube-system`, which is never deleted, so its key survives a reinstall of the Application.
- `.gitleaks.toml` allows SealedSecret ciphertext, which the generic gitleaks rule would otherwise report.
- The alert `SealedSecretNotSynced` fires when a SealedSecret cannot be decrypted for 5 minutes.
