# Attack Surface Recon Pipeline

## Overview

This project is a structured reconnaissance pipeline designed to map and analyze the external attack surface of a target domain. It automates passive and active enumeration, validates outputs at each stage, and produces prioritized findings for further testing.

The focus is not just on collecting data, but on ensuring reliability, filtering noise, and highlighting what actually matters for follow-up analysis.

---

## Objective

The goal of this pipeline is to simulate a real-world reconnaissance workflow used in security and system analysis.

It is designed to:

- Discover and validate subdomains
- Identify live services and exposed infrastructure
- Extract endpoints for further testing
- Highlight high-value targets such as admin panels and API routes
- Provide a clean output that supports decision-making

---

## Workflow

The pipeline follows a staged approach:

1. Subdomain Enumeration  
   Uses subfinder and amass to discover subdomains, then filters and deduplicates results.

2. DNS Resolution  
   Resolves discovered subdomains and extracts valid hostnames and IP addresses.

3. HTTP Probing  
   Identifies live services and collects metadata such as status codes and technologies.

4. Crawling  
   Extracts endpoints from live applications using hakrawler.

5. Analysis and Triage  
   Filters and categorizes endpoints to highlight:
   - API routes
   - authentication-related paths
   - admin interfaces
   - potentially sensitive files

6. Summary Reporting  
   Provides metrics and execution details for quick assessment.

---

## Key Features

### Structured Pipeline Execution
Each stage depends on validated output from the previous step, preventing invalid data from propagating through the pipeline.

### Validation and Failure Awareness
The script includes checks for:
- empty inputs
- missing outputs
- failed tool execution

Warnings are generated when downstream stages may be affected.

### Proxy Support
Optional proxy support using proxychains allows routing traffic through SOCKS proxies or Tor. The script includes a basic sanity check and falls back to direct execution if the proxy is not functioning.

### Output Organization
Results are stored in a timestamped directory with separate folders for:
- passive data
- active scanning results
- screenshots
- triage findings

### Triage and Prioritization
Instead of dumping raw data, the pipeline extracts high-priority findings such as:
- API endpoints
- authentication and admin paths
- sensitive files like .env or .git

This reduces noise and focuses attention on actionable targets.

---

## Relevance to QA / Automation

This project demonstrates a practical approach to validating multi-stage systems rather than just executing tools.

It focuses on:

- Designing and orchestrating structured workflows with clear stage dependencies  
- Validating data at each stage to prevent error propagation  
- Identifying inconsistencies, missing outputs, and unexpected system behavior  
- Understanding how failures in one component impact downstream processes  

These capabilities directly translate to:

- API testing and validation across integrated systems  
- Monitoring and debugging automation workflows  
- Investigating incidents and performing root cause analysis  
- Ensuring reliability and consistency in production pipelines

- ---


## Tools Used

- [`subfinder`](https://github.com/projectdiscovery/subfinder)
- [`amass`](https://github.com/owasp-amass/amass)
- [`dnsx`](https://github.com/projectdiscovery/dnsx)
- [`httpxgo`](https://github.com/projectdiscovery/httpx)
- [`hakrawler`](https://github.com/hakluke/hakrawler)
- [`nmap`](https://nmap.org/)
- [`ffuf`](https://github.com/ffuf/ffuf)
- [`eyewitness`](https://github.com/FortyNorthSecurity/EyeWitness)

---

## Pipeline Overview 

                    +----------------------+
                    |      Input Domain     |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    | Subdomain Enumeration|
                    | (subfinder, amass)   |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    |   Data Cleaning &    |
                    |   Deduplication      |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    |   DNS Resolution     |
                    |       (dnsx)         |
                    +----------+-----------+
                               |
                   +-----------+-----------+
                   |                       |
                   v                       v
         +------------------+     +------------------+
         |   Hostnames      |     |       IPs        |
         +--------+---------+     +--------+---------+
                  |                        |
                  v                        v
         +------------------+     +------------------+
         |   HTTP Probing   |     |   Port/Infra     |
         |     (httpx)      |     |   (optional)     |
         +--------+---------+     +------------------+
                  |
                  v
         +----------------------+
         |     Live URLs        |
         +----------+-----------+
                    |
                    v
         +----------------------+
         |     Crawling         |
         |    (hakrawler)       |
         +----------+-----------+
                    |
                    v
         +----------------------+
         |   Endpoint Extraction|
         +----------+-----------+
                    |
            +-------+--------+
            |                |
            v                v
    +----------------+   +----------------------+
    |  API Detection |   |  Interesting Paths   |
    | (/api, v1, etc)|   | (admin, auth, etc)  |
    +--------+-------+   +----------+-----------+
             |                      |
             +----------+-----------+
                        v
             +----------------------+
             |     Triage Layer     |
             |  (prioritization)    |
             +----------+-----------+
                        |
                        v
             +----------------------+
             |   High Priority      |
             |   Targets Output     |
             +----------+-----------+
                        |
                        v
             +----------------------+
             |   Summary Report     |
             | Metrics + Findings   |
             +----------+-----------+
                        |
                        v
             +----------------------+
             |  Next Step: API Test |
             +----------------------+

---

## Usage

```bash
./recon.sh example.com
```

## Script 

```bash 
#!/bin/bash
# =============================================================
# attack-surface-recon-pipeline — fully validated version
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
```

## Sample Run Output 

[*] Starting Recon Pipeline for: example.com
[*] Output dir : recon-example_com-20260327_120001

[*] Checking proxychains...
[+] Proxychains working

[*] subfinder
[*] dnsx
[*] httpx
[*] Crawling endpoints

=========================================
Target         : example.com
Output Dir     : recon-example_com-20260327_120001
Subdomains     : 42
Resolved       : 30
IPs            : 18
Live Hosts     : 12
Crawled URLs   : 215
API Endpoints  : 14
High Priority  : 9
Errors         : 0
Warnings       : 1
Time           : 58s
=========================================

[*] Next step: Validate high-priority endpoints via API testing
[+] Done → recon-example_com-2026

## Example Output Structure

recon-example_com-YYYYMMDD_HHMMSS/
|
|-- passive/
|   |-- subs.txt
|   |-- amass.txt
|   |-- all_subs.txt
|   |-- dns.txt
|   |-- hosts.txt
|   |-- ips.txt
|   |-- http.txt
|   |-- live.txt
|   |-- crawl.txt
|
|-- active/
|
|-- screenshots/
|
|-- triage/
|   |-- findings.txt
|   |-- high.txt
|
|-- recon.log

## Dependencies

The following tools must be installed and available in PATH:

- subfinder  
- amass  
- dnsx  
- httpx  
- hakrawler  

Optional:

- proxychains  

---

## Design Considerations

This project was built with a focus on:

- reliability over speed
- clean data handling
- minimal assumptions about tool output
- clear separation between data collection and analysis

Each stage is designed to fail safely and provide enough context to understand what went wrong.

---

## Relevance

This project demonstrates:

- workflow orchestration across multiple tools
- data validation and filtering
- handling of partial failures in pipelines
- analysis and prioritization of results
- understanding of how systems expose attack surfaces

These concepts are directly applicable to roles involving:

- API testing and validation
- automation workflows
- system analysis and debugging
- security and reconnaissance

---

## Next Steps

The output of this pipeline is intended to feed into deeper testing.

Typical follow-up activities include:

- API testing of discovered endpoints
- authentication and authorization checks
- fuzzing and input validation
- manual analysis of high-priority targets

---

## Notes

This project is intended for educational and authorized testing environments only. Always ensure you have permission before running reconnaissance against any target.


## 🌐 Proxychains Support
Some tools like subfinder, amass, and httpxgo are executed through proxychains to route traffic via configured SOCKS proxies or Tor for anonymized reconnaissance.

Make sure your proxy settings are correctly configured in `/etc/proxychains.conf`, and test with:

```bash
proxychains curl https://ifconfig.me
```
To disable proxying, comment out or remove proxychains from the relevant lines in recon.sh.

## Prerequisites
Make sure these tools are installed and available in $PATH. Use apt, go install, or your package manager of choice to install them.


## Notes
Wordlist path is hardcoded to /usr/share/wordlists/dirb/common.txt. Adjust as needed.

Eyewitness assumes GUI dependencies (e.g., for Kali Linux).

httpxgo can be swapped with httpx if you use the regular build.

