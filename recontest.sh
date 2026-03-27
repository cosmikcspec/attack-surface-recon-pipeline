#!/bin/bash
# =============================================================
# attack-surface-recon-pipeline 
# =============================================================

DOMAIN="${1:?Usage: $0 <domain> [wordlist]}"
WORDLIST="${2:-/usr/share/wordlists/dirb/common.txt}"
OUTDIR="recon-$(echo "$DOMAIN" | tr '.' '_')-$(date +%Y%m%d_%H%M%S)"
LOGFILE="$OUTDIR/recon.log"
USE_PROXY="${USE_PROXY:-1}"

mkdir -p "$OUTDIR/passive" "$OUTDIR/active" "$OUTDIR/screenshots" "$OUTDIR/triage"
touch "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

START_TIME=$(date +%s)
ERROR_COUNT=0
WARN_COUNT=0

# ── Dependency check ──────────────────────────────────────────
for tool in subfinder dnsx httpx hakrawler; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[!] Missing dependency: $tool"
        exit 1
    fi
done

# ── Proxy wrapper ─────────────────────────────────────────────
px() {
    if [ "$USE_PROXY" = "1" ]; then
        proxychains -q "$@"
    else
        "$@"
    fi
}

# ── Helpers ───────────────────────────────────────────────────
run() {
    local label="$1"; shift
    echo "[*] $label"
    if ! "$@"; then
        echo "[!] FAILED: $label"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        return 1
    fi
    return 0
}

warn() {
    echo "[!] WARN: $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

count_lines() {
    [ -f "$1" ] && wc -l < "$1" || echo 0
}

echo "================================================="
echo "[*] Starting Recon Pipeline for: $DOMAIN"
echo "[*] Output dir : $OUTDIR"
echo "================================================="

# ── Proxy sanity check ────────────────────────────────────────
if [ "$USE_PROXY" = "1" ]; then
    echo "[*] Checking proxychains..."
    if ! proxychains -q curl -s --max-time 10 https://ifconfig.me >/dev/null; then
        warn "Proxychains failed — disabling proxy usage"
        USE_PROXY=0
    else
        echo "[+] Proxychains working"
    fi
fi

# ── Scope confirmation ────────────────────────────────────────
read -rp "Confirm domain: " CONFIRM
[ "$CONFIRM" != "$DOMAIN" ] && exit 1

# ── Subdomains ───────────────────────────────────────────────
run "subfinder" px subfinder -d "$DOMAIN" -silent -o "$OUTDIR/passive/subs.txt"
px amass enum -passive -d "$DOMAIN" -o "$OUTDIR/passive/amass.txt" || warn "amass partial"

cat "$OUTDIR/passive/subs.txt" "$OUTDIR/passive/amass.txt" 2>/dev/null \
    | grep "\.$DOMAIN$" | sort -u > "$OUTDIR/passive/all_subs.txt"

SUB_COUNT=$(count_lines "$OUTDIR/passive/all_subs.txt")

if [ "$SUB_COUNT" -eq 0 ]; then
    echo "[!] No subdomains found — exiting"
    exit 1
fi

# ── DNS ──────────────────────────────────────────────────────
if [ ! -s "$OUTDIR/passive/all_subs.txt" ]; then
    echo "[!] No valid subdomains — exiting"
    exit 1
fi

run "dnsx" px dnsx -l "$OUTDIR/passive/all_subs.txt" -o "$OUTDIR/passive/dns.txt"
RESOLVED_COUNT=$(count_lines "$OUTDIR/passive/dns.txt")

if [ "$RESOLVED_COUNT" -eq 0 ]; then
    warn "No DNS results — downstream may fail"
fi

awk '{if ($1!="") print $1}' "$OUTDIR/passive/dns.txt" > "$OUTDIR/passive/hosts.txt"
grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$OUTDIR/passive/dns.txt" \
    | sort -u > "$OUTDIR/passive/ips.txt"

IP_COUNT=$(count_lines "$OUTDIR/passive/ips.txt")

# ── HTTP ─────────────────────────────────────────────────────
if [ ! -s "$OUTDIR/passive/hosts.txt" ]; then
    warn "No hosts to probe — skipping httpx"
    LIVE_COUNT=0
else
    run "httpx" px httpx -l "$OUTDIR/passive/hosts.txt" -o "$OUTDIR/passive/http.txt" -silent
    LIVE_COUNT=$(count_lines "$OUTDIR/passive/http.txt")
fi

if [ "$LIVE_COUNT" -eq 0 ]; then
    warn "No live hosts — skipping crawling"
fi

awk '{if ($1!="") print $1}' "$OUTDIR/passive/http.txt" > "$OUTDIR/passive/live.txt"

# ── Crawling ─────────────────────────────────────────────────
CRAWLED=0
if [ "$LIVE_COUNT" -gt 0 ]; then
    echo "[*] Crawling endpoints"
    if ! px hakrawler -d 2 -u < "$OUTDIR/passive/live.txt" > "$OUTDIR/passive/crawl.txt" 2>/dev/null; then
        warn "hakrawler failed"
    fi
    CRAWLED=$(count_lines "$OUTDIR/passive/crawl.txt")
fi

# ── API count ────────────────────────────────────────────────
API_COUNT=0
if [ -s "$OUTDIR/passive/crawl.txt" ]; then
    API_COUNT=$(grep -ciE '/api|graphql|/v[0-9]' "$OUTDIR/passive/crawl.txt" 2>/dev/null || echo 0)
fi

# ── Triage ───────────────────────────────────────────────────
TRIAGE="$OUTDIR/triage/findings.txt"
HIGH="$OUTDIR/triage/high.txt"

if [ -s "$OUTDIR/passive/crawl.txt" ]; then
    {
        grep -iE '/api|graphql|/v[0-9]' "$OUTDIR/passive/crawl.txt" 2>/dev/null || true
        grep -iE '(admin|login|auth|\.env|\.git)' "$OUTDIR/passive/crawl.txt" 2>/dev/null || true
    } > "$TRIAGE"

    grep -iE '(admin|login|auth|api|\.env|\.git)' "$OUTDIR/passive/crawl.txt" 2>/dev/null > "$HIGH"
fi

HIGH_COUNT=$(count_lines "$HIGH")

# ── Summary ───────────────────────────────────────────────────
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "========================================="
echo "Target         : $DOMAIN"
echo "Output Dir     : $OUTDIR"
echo "Subdomains     : $SUB_COUNT"
echo "Resolved       : $RESOLVED_COUNT"
echo "IPs            : $IP_COUNT"
echo "Live Hosts     : $LIVE_COUNT"
echo "Crawled URLs   : $CRAWLED"
echo "API Endpoints  : $API_COUNT"
echo "High Priority  : $HIGH_COUNT"
echo "Errors         : $ERROR_COUNT"
echo "Warnings       : $WARN_COUNT"
echo "Time           : ${DURATION}s"
echo "========================================="

echo "[*] Next step: Validate high-priority endpoints via API testing"
echo "[+] Done → $OUTDIR"
