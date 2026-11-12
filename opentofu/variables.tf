variable "ssh_public_key_file" {
  description = "Public key that may log in to the VMs"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "state_passphrase" {
  description = "Passphrase for state and plan encryption"
  type        = string
  sensitive   = true
}
