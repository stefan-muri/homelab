# Rebuild

Building the cluster from scratch. Application data on `local-path` volumes is not restored by these steps.

## Prerequisites

Configured outside this repository:

- Proxmox VE cluster with a resource pool `k3s`
- Debian 13 generic cloud image at `local:import/debian-13-genericcloud-amd64.qcow2` on each host
- Resource mapping `igpu` for the GVT-g device on tojo
- NFS server and restic REST server on tojo

Tools: OpenTofu, Ansible, kubectl, Helm, kubeseal, direnv. Credentials as described in [opentofu.md](opentofu.md).

## Steps

1. Create the VMs. This also writes `ansible/inventory/hosts.yaml`.

   ```sh
   cd opentofu
   tofu init
   tofu apply
   cd ..
   ```

2. Configure the nodes and install k3s. The GPU node switches to the standard Debian kernel and is rebooted before k3s is installed.

   ```sh
   cd ansible
   ansible-playbook playbooks/base.yaml
   ansible-playbook playbooks/gpu.yaml
   ansible gpu -b -m ansible.builtin.reboot
   ansible-playbook playbooks/k3s.yaml
   cd ..
   ```

3. Retrieve the kubeconfig:

   ```sh
   ssh debian@10.0.0.41 sudo cat /etc/rancher/k3s/k3s.yaml | sed 's/127.0.0.1/10.0.0.40/' > ~/.kube/config
   ```

4. Restore the Sealed Secrets key from the password manager. This must happen before Argo CD installs the controller. Otherwise the controller generates a new key and cannot decrypt the SealedSecrets in Git.

   ```sh
   kubectl apply -f sealed-secrets-key.json
   rm sealed-secrets-key.json
   ```

5. Install Argo CD and apply the root application:

   ```sh
   helm repo add argo https://argoproj.github.io/argo-helm
   helm upgrade --install argocd argo/argo-cd --version 10.14.0 \
     --namespace argocd --create-namespace -f kubernetes/argocd/values.yaml
   kubectl apply -f kubernetes/root.yaml
   kubectl -n argocd delete secret -l owner=helm,name=argocd
   ```

   The chart version must match `kubernetes/apps/argocd.yaml`. Deleting the Helm release secret hands the release over to Argo CD. Afterwards, sync the `argocd` application once, change the initial admin password and delete `argocd-initial-admin-secret`.

6. Applications whose first sync fails because a CRD did not exist yet (for example Traefik before cert-manager) need to be synced again.

The Cloudflare configuration is not affected by a cluster rebuild. The tunnel token is part of the SealedSecrets.

## If the controller started before the key was restored

The controller has generated its own key, and the SealedSecrets show `SYNCED False`.

1. Apply the backed-up key as in step 4.
2. Delete the key Secret the controller generated, so that new SealedSecrets are not encrypted with it. It is the one whose name differs from the backup:

   ```sh
   kubectl -n kube-system get secrets -l sealedsecrets.bitnami.com/sealed-secrets-key
   kubectl -n kube-system delete secret <generated-key-name>
   ```

3. Restart the controller. It loads the restored key and decrypts all SealedSecrets again.

   ```sh
   kubectl -n kube-system rollout restart deployment sealed-secrets-controller
   ```
