resource "cloudflare_zero_trust_tunnel_cloudflared" "k3s" {
  account_id = data.cloudflare_zone.main.account.id
  name       = "k3s"
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "k3s" {
  account_id = data.cloudflare_zone.main.account.id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.k3s.id
  config = {
    ingress = [
      {
        service = "http://traefik-public.traefik.svc.cluster.local"
      }
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "k3s" {
  account_id = data.cloudflare_zone.main.account.id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.k3s.id
}

output "tunnel_token" {
  value     = data.cloudflare_zero_trust_tunnel_cloudflared_token.k3s.token
  sensitive = true
}
