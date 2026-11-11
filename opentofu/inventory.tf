resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory/hosts.yaml"
  content = templatefile("${path.module}/templates/hosts.yaml.tftpl", {
    hosts     = local.k3s_hosts
    gpu_hosts = local.gpu_hosts
  })
  file_permission = "0644"
}
