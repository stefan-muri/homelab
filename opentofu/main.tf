locals {
  gateway = "10.0.0.138"

  k3s_nodes = {
    dojo = { vm_id = 141, ip = "10.0.0.41", datastore = "local-zfs", memory = 6144}
    tojo = { vm_id = 241, ip = "10.0.0.42", datastore = "tojo-data", memory = 4096}
    mojo = { vm_id = 341, ip = "10.0.0.43", datastore = "local-zfs", memory = 3072}

  }

  k3s_hosts = { for k, v in local.k3s_nodes : "k3s-${k}" => v.ip }

}
resource "proxmox_virtual_environment_vm" "k3s" {
  for_each = local.k3s_nodes

  name        = "k3s-${each.key}"
  node_name   = each.key
  vm_id       = each.value.vm_id
  pool_id     = "k3s"
  description = "k3s node, managed by OpenTofu"

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
    floating  = each.value.memory
  }

  disk {
    datastore_id = each.value.datastore
    import_from  = "local:import/debian-13-genericcloud-amd64.qcow2"
    interface    = "scsi0"
    size         = 40
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    datastore_id = each.value.datastore


    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = local.gateway
      }
    }

    dns {
      servers = [local.gateway]
    }

    user_account {
      username = "debian"
      keys     = [trimspace(file(pathexpand(var.ssh_public_key_file)))]
    }
  }
  agent {
    enabled = true
  }

  operating_system {
    type = "l26"
  }
  serial_device {}
}
