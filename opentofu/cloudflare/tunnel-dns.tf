locals {
  tunnel_cname = "${cloudflare_zero_trust_tunnel_cloudflared.k3s.id}.cfargotunnel.com"

  # Public hostnames served through the k3s tunnel, and the zone each one is in.
  tunnel_hostnames = {
    "home.unterhaken.at" = data.cloudflare_zone.main.id
    "taxmirror.eu"       = data.cloudflare_zone.taxmirror.id
    "www.taxmirror.eu"   = data.cloudflare_zone.taxmirror.id
  }
}

resource "cloudflare_dns_record" "tunnel" {
  for_each = local.tunnel_hostnames

  zone_id = each.value
  name    = each.key
  type    = "CNAME"
  content = local.tunnel_cname
  ttl     = 1
  proxied = true
  comment = "k3s tunnel, managed by OpenTofu"
}

import {
  to = cloudflare_dns_record.tunnel["home.unterhaken.at"]
  id = "3faa991efaf6651816e062f3780c1d85/3464ba2f491fb00193476b0ab50f7b38"
}
import {
  to = cloudflare_dns_record.tunnel["taxmirror.eu"]
  id = "f7a26c9caba70e6930eab6aae1948add/2d07e890980d4b1bab12e532c9641c13"
}
