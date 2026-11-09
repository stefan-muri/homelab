locals {
  zone = "unterhaken.at"

  ingress_ip = "10.0.0.45"
}

data "cloudflare_zone" "main" {
  filter = {
    name = local.zone
  }
}

data "cloudflare_zone" "taxmirror" {
  filter = {
    name = "taxmirror.eu"
  }
}

resource "cloudflare_dns_record" "k8s_wildcard" {
  zone_id = data.cloudflare_zone.main.id
  name    = "*.k8s.${local.zone}"
  type    = "A"
  content = local.ingress_ip
  ttl     = 1
  proxied = false
  comment = "k3s internal gateway, managed by OpenTofu"
}
