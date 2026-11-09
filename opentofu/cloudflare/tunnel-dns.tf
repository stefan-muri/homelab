locals {
  tunnel_cname = "${cloudflare_zero_trust_tunnel_cloudflared.k3s.id}.cfargotunnel.com"

  # Public hostnames served through the k3s tunnel, and the zone each one is in.
  tunnel_hostnames = {
    "home.unterhaken.at" = data.cloudflare_zone.main.id
    "taxmirror.eu"       = data.cloudflare_zone.taxmirror.id
    "www.taxmirror.eu"   = data.cloudflare_zone.taxmirror.id
    "daelite.at"         = data.cloudflare_zone.daelite.id
    "www.daelite.at"     = data.cloudflare_zone.daelite.id

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
import {
  to = cloudflare_dns_record.tunnel["daelite.at"]
  id = "42408307f13c3c91e0fcb6836819ca03/e4db291f95ad6dfbdbda6cfd1f9a278d"
}
import {
  to = cloudflare_dns_record.tunnel["www.daelite.at"]
  id = "42408307f13c3c91e0fcb6836819ca03/86f57a1b3504bb1a1c053946923ec88d"
}
