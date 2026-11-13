# OpenTofu

There are two configurations, each with its own state:

| Directory | Manages |
|---|---|
| `opentofu/` | Proxmox VMs, generates `ansible/inventory/hosts.yaml` |
| `opentofu/cloudflare/` | DNS records and the Cloudflare Tunnel |

## State

Both states are stored in the Cloudflare R2 bucket `homelab-tofu-state`, under `proxmox/terraform.tfstate` and `cloudflare/terraform.tfstate`. OpenTofu encrypts state and plan files with a key derived from a passphrase (PBKDF2, AES-GCM), so R2 only holds ciphertext. Encryption is enforced: OpenTofu refuses to write unencrypted state.

There is no state locking. Only one machine runs OpenTofu.

## Credentials

direnv loads the credentials from the macOS Keychain when entering either directory (`opentofu/.envrc`, `opentofu/cloudflare/.envrc`).

| Keychain entry | Variable | Value |
|---|---|---|
| `homelab-r2-access-key-id` | `AWS_ACCESS_KEY_ID` | R2 API token, access key ID |
| `homelab-r2-secret-access-key` | `AWS_SECRET_ACCESS_KEY` | R2 API token, secret access key |
| `homelab-r2-endpoint` | `AWS_ENDPOINT_URL_S3` | `https://<account-id>.r2.cloudflarestorage.com` |
| `homelab-tofu-state-passphrase` | `TF_VAR_state_passphrase` | State encryption passphrase |
| `homelab-proxmox-api-token` | `PROXMOX_VE_API_TOKEN` | `user@realm!token-id=secret` |
| `homelab-cloudflare-api-token` | `CLOUDFLARE_API_TOKEN` | Cloudflare API token, only in `opentofu/cloudflare/` |

The values are kept in a password manager. The R2 API token is scoped to the state bucket.

## Setup on a new machine

Store each value in the Keychain. Each command prompts for the value:

```sh
security add-generic-password -a "$USER" -s homelab-r2-access-key-id -U -w
security add-generic-password -a "$USER" -s homelab-r2-secret-access-key -U -w
security add-generic-password -a "$USER" -s homelab-r2-endpoint -U -w
security add-generic-password -a "$USER" -s homelab-tofu-state-passphrase -U -w
security add-generic-password -a "$USER" -s homelab-proxmox-api-token -U -w
security add-generic-password -a "$USER" -s homelab-cloudflare-api-token -U -w
```

Allow the two `.envrc` files and initialize both configurations:

```sh
direnv allow opentofu
direnv allow opentofu/cloudflare
cd opentofu && tofu init && cd cloudflare && tofu init && cd ../..
```

`-U` updates an existing entry, so the same commands also rotate a value.

## Usage

```sh
cd opentofu
tofu plan
tofu apply
```

Changing the memory of a k3s VM restarts it. Drain the node first and uncordon it afterwards.
