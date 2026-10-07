#!/data/data/com.termux/files/usr/bin/sh

# Configura HTTPS per api_server.rb (necessario per la PWA) usando:
#   - DuckDNS: nome pubblico che punta all'IP Tailscale dell'A51
#   - acme.sh: certificato Let's Encrypt via challenge DNS (l'A51 non deve essere esposto su Internet)
#   - Puma: serve HTTPS direttamente sulla porta SPESA_HTTPS_PORT (default 4443)
#
# Uso (sul telefono di produzione, in Termux):
#   DUCKDNS_TOKEN=<token> sh scripts/setup_https_duckdns.sh <sottodominio> [ip_tailscale]
#
#   <sottodominio>  es. "spesa-xxx" per spesa-xxx.duckdns.org
#   [ip_tailscale]  opzionale: se indicato aggiorna il record A su DuckDNS (es. 100.101.102.103)
#
# Rieseguibile: se il certificato è già valido acme.sh non lo richiede di nuovo.
# Il rinnovo è automatico (cron di acme.sh) e riavvia solo l'API con check_spesa.sh restart-api.

set -e

TERMUX_HOME="${TERMUX_HOME:-/data/data/com.termux/files/home}"
SPESA_DIR="${SPESA_DIR:-$TERMUX_HOME/spesa}"
CERT_DIR="$SPESA_DIR/certs"
HTTPS_PORT="${SPESA_HTTPS_PORT:-4443}"
ACME_HOME="$HOME/.acme.sh"
ACME="$ACME_HOME/acme.sh"

SUBDOMAIN="${1:-}"
TAILSCALE_IP="${2:-}"

fail() {
  echo "[https] ERRORE: $1" >&2
  exit 1
}

[ -n "$SUBDOMAIN" ] || fail "uso: DUCKDNS_TOKEN=<token> sh $0 <sottodominio> [ip_tailscale]"
[ -n "$DUCKDNS_TOKEN" ] || fail "variabile DUCKDNS_TOKEN mancante (la trovi su duckdns.org)"
SUBDOMAIN="${SUBDOMAIN%.duckdns.org}"
DOMAIN="$SUBDOMAIN.duckdns.org"

for bin in curl openssl crontab; do
  command -v "$bin" >/dev/null 2>&1 || fail "'$bin' non trovato: pkg install curl openssl-tool cronie"
done

# 1. Puma deve essere compilato con supporto SSL
cd "$SPESA_DIR"
if ! bundle exec ruby -e 'require "puma"; exit(Puma.ssl? ? 0 : 1)'; then
  fail "Puma senza SSL. Prova: pkg install openssl && bundle pristine puma"
fi
echo "[https] Puma con SSL: ok"

# 2. Record A su DuckDNS -> IP Tailscale (solo se passato)
if [ -n "$TAILSCALE_IP" ]; then
  RESP=$(curl -fsS "https://www.duckdns.org/update?domains=$SUBDOMAIN&token=$DUCKDNS_TOKEN&ip=$TAILSCALE_IP")
  [ "$RESP" = "OK" ] || fail "aggiornamento DuckDNS fallito (risposta: $RESP)"
  echo "[https] $DOMAIN -> $TAILSCALE_IP"
fi

# 3. acme.sh (installa anche il proprio cron di rinnovo)
if [ ! -x "$ACME" ]; then
  echo "[https] installazione acme.sh..."
  curl -fsSL https://get.acme.sh | sh
fi
[ -x "$ACME" ] || fail "acme.sh non installato in $ACME_HOME"

# 4. Emissione certificato (DuckDNS_Token viene salvato da acme.sh in account.conf)
export DuckDNS_Token="$DUCKDNS_TOKEN"
set +e
"$ACME" --issue --dns dns_duckdns -d "$DOMAIN" --server letsencrypt
RC=$?
set -e
# rc 2 = certificato già valido, nessun rinnovo necessario
[ "$RC" -eq 0 ] || [ "$RC" -eq 2 ] || fail "emissione certificato fallita (rc=$RC)"

# 5. Installazione nella cartella del progetto + comando di riavvio per i rinnovi
mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"
"$ACME" --install-cert -d "$DOMAIN" \
  --key-file "$CERT_DIR/key.pem" \
  --fullchain-file "$CERT_DIR/fullchain.pem" \
  --reloadcmd "sh $SPESA_DIR/check_spesa.sh restart-api"
chmod 600 "$CERT_DIR/key.pem"

echo "[https] fatto. Verifica da iPhone/PC (con Tailscale attivo):"
echo "        curl -H 'Authorization: Bearer <api_token>' https://$DOMAIN:$HTTPS_PORT/ping"
