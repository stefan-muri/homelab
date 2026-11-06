resource "proxmox_virtual_environment_vm" "test"{
    name = "tofu-test"
    node_name = "mojo"
    vm_id = 349
    pool_id = "k3s"

    cpu {
      cores = 1
    }

    memory {
      dedicated = 1024
    }

    disk {
      datastore_id = "local-zfs"
      import_from = "local:import/debian-13-genericcloud-amd64.qcow2"
      interface = "scsi0"
      size = 10
    }

    network_device {
      bridge = "vmbr0"
    }

    initialization {
      datastore_id = "local-zfs"


      ip_config {
        ipv4 {
          address = "10.0.0.49/24"
          gateway = "10.0.0.138"
        }
      }

      dns {
        servers= ["10.0.0.138"]

      }

      user_account {
        username = "debian"
        keys = [trimspace(file(pathexpand(var.ssh_public_key_file)))]
      }
    }
  agent {
    enabled = false
  }

  operating_system {
    type = "l26"
  }
  serial_device {}
}
