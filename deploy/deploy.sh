#!/usr/bin/env bash
# Publishes CyberSweeper's download page and builds on the server.
#
#   deploy/deploy.sh [release-folder]      (default: the repo's dist/)
#
# The site's address and tunnel come from deploy/site.env, which stays on the
# server and is never committed (see deploy/site.env.example).
#
# Run it as yourself, not with sudo: it asks for sudo only on the steps that
# need it, explains each step before doing it, and asks before changing any
# system config. Steps already done are skipped, so running it again for each
# new release only publishes the files. deploy/README.md explains every step.

set -euo pipefail

say() { printf '\n== %s\n' "$*"; }
explain() { printf '   %s\n' "$@"; }
ask() { local a; read -r -p "   $1 [y/N] " a; [[ $a == [yY]* ]]; }
die() { printf '\ndeploy stopped: %s\n' "$*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "run this as yourself, not with sudo; it uses sudo only where it has to"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_ENV="$REPO/deploy/site.env"
[[ -f $SITE_ENV ]] || die "no $SITE_ENV: copy deploy/site.env.example to it and fill in the address and tunnel"
WEBROOT=/var/www/cybersweeper
CF_CONFIG=/etc/cloudflared/config.yml
CF_READY=http://127.0.0.1:20241/ready       # cloudflared's metrics address
# shellcheck source=site.env.example
source "$SITE_ENV"
[[ ${HOST:-} =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]] || die "HOST in $SITE_ENV isn't a hostname"
[[ ${TUNNEL:-} =~ ^[A-Za-z0-9_.-]+$ ]] || die "TUNNEL in $SITE_ENV isn't a tunnel name"
CONF_DST=/etc/nginx/conf.d/cybersweeper.conf
ARCHIVES=(CyberSweeper-windows.zip CyberSweeper-macos.zip CyberSweeper-linux.tar.gz)
SRC="$(cd "${1:-$REPO/dist}" && pwd)"
# deploy/cybersweeper.conf with this site's address filled in.
CONF_SRC="$(mktemp)"
trap 'rm -f "$CONF_SRC"' EXIT
[[ $WEBROOT =~ ^/[A-Za-z0-9_./-]+$ ]] || die "WEBROOT in $SITE_ENV isn't a plain absolute path"
sed -e "s/__HOST__/$HOST/g" -e "s#__WEBROOT__#$WEBROOT#g" "$REPO/deploy/cybersweeper.conf" > "$CONF_SRC"

# --- 1. the release ---------------------------------------------------------------
say "1. Checking the release in $SRC"
for f in index.html SHA256SUMS "${ARCHIVES[@]}"; do
    [[ -f $SRC/$f ]] || die "$SRC/$f is missing (build it with: python3 tools/build.py)"
done
(cd "$SRC" && sha256sum --quiet -c SHA256SUMS) || die "a download doesn't match SHA256SUMS; rebuild or re-copy it"
for f in "${ARCHIVES[@]}"; do
    grep -q " $f\$" "$SRC/SHA256SUMS" || die "SHA256SUMS doesn't list $f"
done
while read -r sum name; do
    grep -q "$sum" "$SRC/index.html" || die "the page doesn't show $name's checksum; run: python3 tools/build.py --page-only"
done < "$SRC/SHA256SUMS"
VERSION="$(grep -o 'CyberSweeper v[0-9][0-9.]*[0-9]' "$SRC/index.html" | head -n 1 | cut -c15-)"
explain "release $VERSION: all five files are here, the downloads match SHA256SUMS, and the page shows the same checksums"

# --- 2. the web folder ------------------------------------------------------------
say "2. The web folder, $WEBROOT"
if [[ -d $WEBROOT ]]; then
    explain "already there"
else
    explain "Creates $WEBROOT, owned by you, so publishing a"
    explain "release needs no sudo. restorecon gives it the SELinux label the rest of"
    explain "/var/www already has (httpd_sys_content_t), which lets nginx read it. No"
    explain "new SELinux rule is needed."
    ask "Create it?" || die "stopped before creating $WEBROOT"
    sudo install -d -o "$USER" -g "$(id -gn)" -m 755 "$WEBROOT"
    sudo restorecon -R "$WEBROOT"
fi

# --- 3. nginx ---------------------------------------------------------------------
say "3. The nginx site, $CONF_DST"
if sudo test -f "$CONF_DST" && sudo cmp -s "$CONF_SRC" "$CONF_DST"; then
    explain "up to date"
else
    explain "Installs deploy/cybersweeper.conf for $HOST: it listens on"
    explain "127.0.0.1:80 only and serves just the page, SHA256SUMS and"
    explain "the three downloads. nginx -t checks the whole config before nginx"
    explain "reloads; a reload doesn't drop anyone's connection."
    backup=""
    if sudo test -f "$CONF_DST"; then
        explain "Changes from the installed copy:"
        sudo diff -u "$CONF_DST" "$CONF_SRC" || true
        backup="$CONF_DST.bak-$(date +%Y%m%d-%H%M%S)"
    fi
    ask "Install it and reload nginx?" || die "stopped before changing nginx"
    # The backup goes outside conf.d, where nginx would load it as a second site.
    [[ -n $backup ]] && backup="/etc/nginx/$(basename "$backup")" && sudo cp -p "$CONF_DST" "$backup"
    sudo install -o root -g root -m 644 "$CONF_SRC" "$CONF_DST"
    sudo restorecon "$CONF_DST"
    if ! sudo nginx -t; then
        if [[ -n $backup ]]; then sudo cp -p "$backup" "$CONF_DST"; else sudo rm -f "$CONF_DST"; fi
        die "nginx -t failed, so the previous config is back and nginx wasn't reloaded"
    fi
    sudo systemctl reload nginx
fi

# --- 4. the Cloudflare tunnel -----------------------------------------------------
say "4. The Cloudflare tunnel ($TUNNEL)"
if sudo grep -q "hostname: $HOST" "$CF_CONFIG"; then
    explain "$HOST is already in it"
else
    explain "Adds $HOST to the existing '$TUNNEL' tunnel, just before its final"
    explain "catch-all 404 rule:"
    explain "    - hostname: $HOST" "      service: http://127.0.0.1:80"
    explain "config.yml is backed up first. cloudflared checks the new rules"
    explain "(ingress validate) and the backup goes back if they don't pass. Then"
    explain "cloudflared restarts, which blips the tunnel's other sites for a few seconds."
    explain "firewalld: nothing changes. The tunnel only connects outward, so no"
    explain "port opens and your IP never appears anywhere."
    ask "Add it and restart cloudflared?" || die "stopped before changing the tunnel"
    backup="$CF_CONFIG.bak-$(date +%Y%m%d-%H%M%S)"
    sudo cp -p "$CF_CONFIG" "$backup"
    # Insert before the catch-all, matching its indentation. tee keeps the
    # file's owner and mode (root:cloudflared 0640).
    sudo awk -v host="$HOST" '
        !done && /^[[:space:]]*- service:[[:space:]]*http_status:404/ {
            ind = $0; sub(/-.*/, "", ind)
            print ind "- hostname: " host
            print ind "  service: http://127.0.0.1:80"
            done = 1
        }
        { print }
        END { if (!done) exit 3 }
    ' "$backup" | sudo tee "$CF_CONFIG" > /dev/null \
        || { sudo cp -p "$backup" "$CF_CONFIG"; die "couldn't find the catch-all 404 rule in $CF_CONFIG; it's unchanged"; }
    if ! sudo cloudflared tunnel --config "$CF_CONFIG" ingress validate; then
        sudo cp -p "$backup" "$CF_CONFIG"
        die "cloudflared didn't accept the new rules, so the backup is back in place"
    fi
    sudo systemctl restart cloudflared
    for _ in $(seq 30); do
        curl -fsS "$CF_READY" > /dev/null 2>&1 && break
        sleep 1
    done
    curl -fsS "$CF_READY" > /dev/null 2>&1 || die "cloudflared isn't ready after a restart; check: systemctl status cloudflared"
    explain "cloudflared is back up (backup at $backup)"
fi

# --- 5. DNS -----------------------------------------------------------------------
say "5. The DNS name, $HOST"
if getent hosts "$HOST" > /dev/null; then
    explain "already resolves"
else
    explain "cloudflared tunnel route dns makes $HOST a proxied CNAME to the tunnel"
    explain "(<tunnel id>.cfargotunnel.com), so there's no A record with your home IP."
    explain "It runs as you, because it needs your account certificate in"
    explain "~/.cloudflared/cert.pem."
    ask "Create the DNS record?" || die "stopped before creating the DNS record"
    cloudflared tunnel route dns "$TUNNEL" "$HOST"
fi

# --- 6. publish -------------------------------------------------------------------
say "6. Publishing $VERSION into $WEBROOT"
explain "The downloads and SHA256SUMS go first and the page last, so the live page"
explain "never points at files that aren't there yet. Each file is copied next to"
explain "its old one and then swapped in."
for f in "${ARCHIVES[@]}" SHA256SUMS index.html; do
    install -m 644 "$SRC/$f" "$WEBROOT/.$f.new"
    mv -f "$WEBROOT/.$f.new" "$WEBROOT/$f"
done
sudo restorecon -R "$WEBROOT"
extra="$(find "$WEBROOT" -mindepth 1 -maxdepth 1 ! -name index.html ! -name SHA256SUMS ! -name 'CyberSweeper-*' -printf '%f ' 2>/dev/null || true)"
[[ -z $extra ]] || explain "(other files in $WEBROOT, left alone: $extra)"

# --- 7. check ---------------------------------------------------------------------
say "7. Checking it's live"
size_of() { stat -c %s "$1"; }
local_page="$(curl -fsS -H "Host: $HOST" http://127.0.0.1/)" || die "nginx didn't serve the page on loopback"
grep -q "CyberSweeper v$VERSION" <<< "$local_page" || die "nginx serves an older page; is $CONF_DST the one in use?"
for f in "${ARCHIVES[@]}"; do
    len="$(curl -fsSI -H "Host: $HOST" "http://127.0.0.1/$f" | tr -d '\r' | awk 'tolower($1)=="content-length:" {print $2}')"
    [[ $len == "$(size_of "$SRC/$f")" ]] || die "nginx serves $f at $len bytes, not $(size_of "$SRC/$f")"
done
explain "nginx: the page and all three downloads, at the right sizes"
if public="$(curl -fsS --max-time 20 "https://$HOST/SHA256SUMS")"; then
    if [[ $public == "$(cat "$SRC/SHA256SUMS")" ]]; then
        explain "https://$HOST: live, with this release's checksums"
    else
        explain "https://$HOST answers, but with older checksums. That's Cloudflare's"
        explain "cache; it re-checks shortly. Try again in a minute."
    fi
else
    explain "https://$HOST doesn't answer yet. A new DNS name can take a few minutes;"
    explain "run this again later and it'll go straight to this check."
fi
say "Done: https://$HOST"
