# Rebuild

Building the cluster from scratch, or replacing a single node. Application data on `local-path` volumes is not restored by these steps.

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

## Replacing a node

Recreating one VM while the other two nodes keep running. The examples use k3s-mojo (VM 341, 10.0.0.43). Tested on 2026-11-26; it took about 15 minutes.

k3s-mojo holds no `local-path` volumes. On the other nodes the root disk also holds `local-path` volumes (database instances, Prometheus, application configuration), which are lost with the VM.

While the node is out, etcd runs on two of three members. Avoid the backup window (03:00–06:40). If the node is already lost, skip steps 2 to 4; this case has not been tested.

1. Check the plan and take an etcd snapshot. `-target` keeps all other resources out of the run.

   ```sh
   cd opentofu
   tofu plan -replace='proxmox_virtual_environment_vm.k3s["mojo"]' -target='proxmox_virtual_environment_vm.k3s["mojo"]'
   cd ..
   ssh debian@10.0.0.41 sudo k3s etcd-snapshot save --name pre-mojo-rebuild
   ```

   The plan must show `1 to add, 0 to change, 1 to destroy`.

2. Move the Longhorn replicas off the node and wait until none is listed:

   ```sh
   kubectl -n longhorn-system patch nodes.longhorn.io k3s-mojo --type merge \
     -p '{"spec":{"allowScheduling":false,"evictionRequested":true}}'
   kubectl -n longhorn-system get replicas.longhorn.io -o wide | grep k3s-mojo
   ```

3. Drain the node. The eviction of the Longhorn instance manager is retried until its volumes have detached.

   ```sh
   kubectl drain k3s-mojo --ignore-daemonsets --delete-emptydir-data
   ```

4. Shut the VM down on the Proxmox host. It must be stopped before the node is deleted, otherwise k3s registers it again.

   ```sh
   qm shutdown 341 --timeout 180
   ```

5. Delete the node. k3s removes its etcd member and node password Secret, and Longhorn removes its node object.

   ```sh
   kubectl delete node k3s-mojo
   ```

   Check that etcd has two members. `kubectl debug` prints the name of the pod:

   ```sh
   kubectl debug node/k3s-dojo --image=quay.io/coreos/etcd:v3.6.17 --profile=general -- \
     etcdctl --endpoints=https://127.0.0.1:2379 \
     --cacert=/host/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
     --cert=/host/var/lib/rancher/k3s/server/tls/etcd/client.crt \
     --key=/host/var/lib/rancher/k3s/server/tls/etcd/client.key \
     member list -w table
   kubectl logs <pod>
   kubectl delete pod <pod>
   ```

6. Recreate the VM:

   ```sh
   ssh-keygen -R 10.0.0.43
   cd opentofu
   tofu apply -replace='proxmox_virtual_environment_vm.k3s["mojo"]' -target='proxmox_virtual_environment_vm.k3s["mojo"]'
   cd ..
   ```

   The apply waits for the QEMU guest agent, which the cloud image does not contain. In a second terminal, accept the new host key and wait for cloud-init, then start step 7. The apply completes once `base.yaml` has installed the agent.

   ```sh
   ssh debian@10.0.0.43 cloud-init status --wait
   ```

7. Configure the node and join it to the cluster. For k3s-tojo, run `gpu.yaml` and reboot before `k3s.yaml`, as in the full rebuild.

   ```sh
   cd ansible
   ansible-playbook playbooks/base.yaml --limit k3s-mojo
   ansible-playbook playbooks/longhorn.yaml --limit k3s-mojo
   ansible-playbook playbooks/k3s.yaml --limit k3s-mojo
   ```

   `Show what Ansible decided` must report `cluster exists: True` and one of the other nodes as the seed.

8. Check that the node is Ready, that etcd lists three members with none a learner, and that `kubectl -n longhorn-system get nodes.longhorn.io` shows the node as schedulable.

9. Move workloads back. The node comes back empty, and neither Kubernetes nor Longhorn moves pods or replicas to it by themselves. Cordon the other two nodes, restart the workloads that are not pinned to a node one at a time, then uncordon:

   ```sh
   kubectl cordon k3s-dojo k3s-tojo
   kubectl -n paperless rollout restart deployment paperless
   kubectl -n paperless rollout status deployment paperless
   kubectl uncordon k3s-dojo k3s-tojo
   ```

   Applications with a single replica are unavailable for one to two minutes each. For Longhorn, raise a volume to three replicas, wait until the new replica on the node is healthy, and set it back to two. Longhorn keeps the new replica.

   ```sh
   kubectl -n longhorn-system patch volumes.longhorn.io <volume> --type merge -p '{"spec":{"numberOfReplicas":3}}'
   kubectl -n longhorn-system get replicas.longhorn.io -o wide | grep <volume>
   kubectl -n longhorn-system patch volumes.longhorn.io <volume> --type merge -p '{"spec":{"numberOfReplicas":2}}'
   ```
