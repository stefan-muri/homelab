variable "ssh_public_key_file" {
    description = "Public key that may log in to the VMs"
    type = string
    default = "~/.ssh/id_ed25519.pub"
}
