output "k3s_nodes" {
    description = "k3s node name and IP"
    value = {for k, v in local.k3s_nodes: "k3s-${k}" => v.ip}
}
