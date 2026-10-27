# Publishing CyberSweeper

The download page and the three builds are served as static files:
- **nginx**, listening on `127.0.0.1:80` only, with one config file in `/etc/nginx/conf.d/` and one folder under `/var/www/`;
- **an existing Cloudflare tunnel**, which carries the site's hostname to nginx.

Nothing opens to the internet directly.

You run `deploy/deploy.sh` on the server, as yourself. It asks for sudo only where it needs it. Before each step it explains what the step does, and it asks before it changes any system config. The first run sets everything up; after that, each run just publishes the new release.

## 0. Once: the site settings

The site's address and the tunnel's name live in `deploy/site.env` on the server. That file is gitignored, so this public repo never names the site or the server. Copy the example and fill it in:

```bash
cp deploy/site.env.example deploy/site.env
```

```bash
nano deploy/site.env
```

| Setting | What it is |
| --- | --- |
| `HOST` | the site's public address, such as `cybersweeper.example.com` |
| `TUNNEL` | the name of the existing Cloudflare tunnel to add it to |
| `WEBROOT`, `CF_CONFIG`, `CF_READY` | optional; the defaults are `/var/www/cybersweeper`, `/etc/cloudflared/config.yml` and cloudflared's metrics address `http://127.0.0.1:20241/ready` |

## 1. Get a release onto the server

A release is the five files `tools/build.py` writes into `dist/`:
- `index.html`
- `CyberSweeper-windows.zip`
- `CyberSweeper-macos.zip`
- `CyberSweeper-linux.tar.gz`
- `SHA256SUMS`

**Built on a Windows PC.** Windows has no rsync, so copy the folder with scp. In PowerShell, from the repo folder (use your own SSH name for the server):

```powershell
scp -r dist yourserver:~/cybersweeper-upload
```

Then, on the server, get the latest deploy files and publish that folder:

```bash
cd ~/CyberSweeper && git pull
```

```bash
deploy/deploy.sh ~/cybersweeper-upload
```

**Or build on the server itself,** if it has the repo, Godot and the export templates:

```bash
python3 tools/build.py && deploy/deploy.sh
```

With no folder given, the script publishes the repo's `dist/`.

## 2. What the script does

1. **Checks the release.** All five files must be there, `sha256sum -c SHA256SUMS` must pass, and the page must show the same checksums. A half-copied or mismatched release stops here.
2. **The web folder.** Once only, it creates the web folder, owned by you, so publishing needs no sudo. `restorecon` gives it the SELinux label the rest of `/var/www` already uses (`httpd_sys_content_t`), which lets nginx read it. No new SELinux rule or port label is needed, since nginx already serves `127.0.0.1:80`.
3. **nginx.** It fills the site's address into `deploy/cybersweeper.conf` and installs the result as `/etc/nginx/conf.d/cybersweeper.conf`. If the installed copy has changed since last time, it shows the difference and asks first. It then tests the whole config with `nginx -t` and reloads nginx. If the test fails, the previous config goes back and nginx isn't reloaded. The config:
   - listens on loopback only;
   - sends plain-http visitors to https;
   - serves only the page, `SHA256SUMS` and the three downloads, and a 404 for anything else;
   - makes the downloads save as files;
   - tells browsers and Cloudflare to re-check the page and `SHA256SUMS` every time;
   - sets a strict content security policy. The page has everything built in, so it may load nothing from anywhere else.
4. **The Cloudflare tunnel.** Once only, it adds two lines to the tunnel's `config.yml`, just before the final catch-all `http_status:404` rule:

   ```yaml
     - hostname: <HOST>
       service: http://127.0.0.1:80
   ```

   It backs up `config.yml` first, then runs `cloudflared tunnel ingress validate`, and puts the backup back if the rules don't pass. Then it restarts cloudflared and waits until cloudflared reports ready. The restart briefly interrupts the tunnel's other sites, for a few seconds.
5. **DNS.** Once only, it runs `cloudflared tunnel route dns <TUNNEL> <HOST>`. That makes a proxied CNAME to the tunnel, so no A record ever holds the server's IP. It runs as you, not root, because it uses your Cloudflare account certificate in `~/.cloudflared/cert.pem`.
6. **Publishes.** It copies the downloads and `SHA256SUMS` first and the page last, so the live page never links to a file that isn't there yet. Each file is swapped in whole, never half-written.
7. **Checks it's live.** nginx on loopback must serve the new page, and all three downloads at the right sizes. Then the public `https://<HOST>/SHA256SUMS` must match. A brand-new DNS name can take a few minutes to answer; running the script again then goes straight to this check.

**firewalld: nothing changes.** SPEC.md asks the deploy to cover firewalld. Here that means confirming nothing opens: the tunnel only connects outward to Cloudflare, so no inbound port, router forward or firewall rule is involved.

## 3. Updates, rollbacks and Cloudflare's cache

- **New release:** build, copy it over as above, and run the script again. Only step 6 does anything new.
- **Roll back:** run the script on an older release folder. Each one carries its own checksums and page, so they always match.
- **Cloudflare caches `.zip` and `.gz` files.** The page links each download as `CyberSweeper-windows.zip?v=<start of its checksum>`, so every new build gets a new link, and nobody gets an old copy next to new checksums. The page itself and `SHA256SUMS` are re-checked on every visit.

## 4. Taking it down

1. Remove the nginx site:

   ```bash
   sudo rm /etc/nginx/conf.d/cybersweeper.conf && sudo nginx -t && sudo systemctl reload nginx
   ```

2. Delete the two hostname lines from the tunnel's `config.yml`, check it with `sudo cloudflared tunnel --config /etc/cloudflared/config.yml ingress validate`, and restart cloudflared.
3. Remove the DNS record in the Cloudflare dashboard.
4. Delete the web folder once you're sure.
