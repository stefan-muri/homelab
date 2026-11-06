output "k3s_nodes" {
  description = "k3s node name and IP"
  value       = local.k3s_hosts
}
