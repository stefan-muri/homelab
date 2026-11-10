locals {
  # Tuta mail for unterhaken.at. TXT values keep the quotes Cloudflare stores
  # them with, so the imported records match exactly.
  mail_records = {
    mx           = { name = "unterhaken.at", type = "MX", content = "mail.tutanota.de", priority = 10 }
    spf          = { name = "unterhaken.at", type = "TXT", content = "\"v=spf1 include:spf.tutanota.de -all\"", priority = null }
    verification = { name = "unterhaken.at", type = "TXT", content = "\"t-verify=6ee1ba60957728ff314e4079bb823310\"", priority = null }
    dmarc        = { name = "_dmarc.unterhaken.at", type = "TXT", content = "\"v=DMARC1; p=quarantine; adkim=s\"", priority = null }
    dkim_s1      = { name = "s1._domainkey.unterhaken.at", type = "CNAME", content = "s1.domainkey.tutanota.de", priority = null }
    dkim_s2      = { name = "s2._domainkey.unterhaken.at", type = "CNAME", content = "s2.domainkey.tutanota.de", priority = null }
    mta_sts      = { name = "mta-sts.unterhaken.at", type = "CNAME", content = "mta-sts.tutanota.de", priority = null }
    mta_sts_txt  = { name = "_mta-sts.unterhaken.at", type = "CNAME", content = "mta-sts.tutanota.de", priority = null }
  }
}

resource "cloudflare_dns_record" "mail" {
  for_each = local.mail_records

  zone_id  = data.cloudflare_zone.main.id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  priority = each.value.priority
  ttl      = 1
  proxied  = false
  comment  = "Tuta mail, managed by OpenTofu"
}

import {
  to = cloudflare_dns_record.mail["mx"]
  id = "3faa991efaf6651816e062f3780c1d85/f758a3000f9a2a32e6c4d1bbaa3c3c21"
}

import {
  to = cloudflare_dns_record.mail["spf"]
  id = "3faa991efaf6651816e062f3780c1d85/cb6e517cda61f0db304b181a9e643670"
}

import {
  to = cloudflare_dns_record.mail["verification"]
  id = "3faa991efaf6651816e062f3780c1d85/90a58aa8410567791554d9ef8c0615d9"
}

import {
  to = cloudflare_dns_record.mail["dmarc"]
  id = "3faa991efaf6651816e062f3780c1d85/45ffa20df0ed86ba02b1e151f58cc6a1"
}

import {
  to = cloudflare_dns_record.mail["dkim_s1"]
  id = "3faa991efaf6651816e062f3780c1d85/c9f04dc566b45d8157fd2b51ffdea526"
}

import {
  to = cloudflare_dns_record.mail["dkim_s2"]
  id = "3faa991efaf6651816e062f3780c1d85/d0e262e55ac7bcbc24ba152b830d661e"
}

import {
  to = cloudflare_dns_record.mail["mta_sts"]
  id = "3faa991efaf6651816e062f3780c1d85/cdb527dbcbd62e22d5d9ea690526f6ef"
}

import {
  to = cloudflare_dns_record.mail["mta_sts_txt"]
  id = "3faa991efaf6651816e062f3780c1d85/6c280d10a0ebb1f28882a6c9c92a1ade"
}
