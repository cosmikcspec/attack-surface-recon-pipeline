# 🔍 Automated Recon Script

Objective :

This project simulates a structured reconnaissance workflow to map and analyze the external attack surface of a target domain.

The goal is not just enumeration, but identifying:
- exposed services
- potential entry points
- misconfigurations
- areas requiring further validation

This mirrors real-world security and system analysis workflows.

This is a Bash-based automated recon pipeline built for efficient, modular reconnaissance. It performs passive and active enumeration using top-tier tools like `subfinder`, `amass`, `httpxgo`, `dnsx`, `hakrawler`, `nmap`, `ffuf`, and `eyewitness`. 

Many of the tools are routed through `proxychains` to allow traffic anonymization through SOCKS proxies or Tor — giving you stealth where it matters. Output is neatly organized into timestamped directories with subfolders for passive, active, and visual (screenshots) results.

Ideal for CTFs, bug bounty recon, OSINT campaigns, or building a clean GitHub portfolio.


## 📦 Tools Used

- [`subfinder`](https://github.com/projectdiscovery/subfinder)
- [`amass`](https://github.com/owasp-amass/amass)
- [`dnsx`](https://github.com/projectdiscovery/dnsx)
- [`httpxgo`](https://github.com/projectdiscovery/httpx)
- [`hakrawler`](https://github.com/hakluke/hakrawler)
- [`nmap`](https://nmap.org/)
- [`ffuf`](https://github.com/ffuf/ffuf)
- [`eyewitness`](https://github.com/FortyNorthSecurity/EyeWitness)

## 🚀 Usage

```bash
./recon.sh example.com
```

## Script 

```bash 
#!/bin/bash
set -e

DOMAIN="$1"
OUTDIR="recon-$DOMAIN"
mkdir -p "$OUTDIR/passive" "$OUTDIR/active" "$OUTDIR/screenshots"

# ================== LOGGING SETUP ==================
LOGFILE="$OUTDIR/recon.log"
touch "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

# ================== TIMER ==================
START_TIME=$(date +%s)

# ================== ERROR TRACKING ==================
ERROR_COUNT=0

echo "================================================="
echo "[*] Starting Recon Pipeline for: $DOMAIN"
echo "================================================="

# ================== SUBDOMAIN ENUM ==================
echo "[*] Running subfinder..."
proxychains subfinder -d "$DOMAIN" -o "$OUTDIR/passive/subdomains_subfinder.txt"

echo "[*] Running amass..."
proxychains amass enum -passive -d "$DOMAIN" -o "$OUTDIR/passive/subdomains_amass.txt"

echo "[*] Combining subdomains..."
cat "$OUTDIR/passive"/subdomains_*.txt | sort -u > "$OUTDIR/passive/subdomains_combined.txt"

# ===== VALIDATION 1 =====
echo "[*] Validating combined subdomains..."
SUB_COUNT=$(wc -l < "$OUTDIR/passive/subdomains_combined.txt")
echo "[+] Total unique subdomains: $SUB_COUNT"
TOTAL_SUBS=$SUB_COUNT

if [ "$SUB_COUNT" -eq 0 ]; then
    echo "[!] No subdomains found. Exiting."
    ERROR_COUNT=$((ERROR_COUNT + 1))
    exit 1
fi

# ================== DNS RESOLUTION ==================
echo "[*] Resolving subdomains with dnsx..."
proxychains dnsx -l "$OUTDIR/passive/subdomains_combined.txt" -o "$OUTDIR/passive/dns_resolved.txt"

# ===== VALIDATION 2 =====
echo "[*] Validating resolved domains..."
RESOLVED_COUNT=$(wc -l < "$OUTDIR/passive/dns_resolved.txt")
echo "[+] Resolved domains: $RESOLVED_COUNT"
TOTAL_RESOLVED=$RESOLVED_COUNT

if [ "$RESOLVED_COUNT" -eq 0 ]; then
    echo "[!] No domains resolved. Possible DNS or input issue."
    ERROR_COUNT=$((ERROR_COUNT + 1))
fi

# ================== HTTP PROBING ==================
echo "[*] Probing HTTP/S services with httpx..."
proxychains httpxgo -l "$OUTDIR/passive/dns_resolved.txt" \
    -o "$OUTDIR/passive/httpx_live_hosts.txt" \
    -tech-detect -status-code -title

# ===== VALIDATION 3 =====
echo "[*] Validating live hosts..."
if [ ! -s "$OUTDIR/passive/httpx_live_hosts.txt" ]; then
    echo "[!] No live HTTP hosts found."
    TOTAL_LIVE=0
    ERROR_COUNT=$((ERROR_COUNT + 1))
else
    LIVE_COUNT=$(wc -l < "$OUTDIR/passive/httpx_live_hosts.txt")
    echo "[+] Live hosts detected: $LIVE_COUNT"
    TOTAL_LIVE=$LIVE_COUNT
fi

# ================== CRAWLING ==================
echo "[*] Crawling live endpoints with hakrawler..."
echo "$DOMAIN" | hakrawler -d 2 -u > "$OUTDIR/passive/hakrawler_urls.txt"

# ================== PORT SCAN ==================
echo "[*] Running Nmap scan..."
proxychains nmap -iL "$OUTDIR/passive/dns_resolved.txt" -T4 -Pn \
    -oN "$OUTDIR/active/portscan_nmap.txt"

# ================== FUZZING ==================
echo "[*] Fuzzing common admin dirs with ffuf..."
ffuf -w /usr/share/wordlists/dirb/common.txt \
    -u "https://$DOMAIN/FUZZ" \
    -o "$OUTDIR/active/fuzz_ffuf_admin.txt"

# ================== SCREENSHOTS ==================
echo "[*] Taking screenshots with eyewitness..."
eyewitness --web \
    -f "$OUTDIR/passive/httpx_live_hosts.txt" \
    -d "$OUTDIR/screenshots/eyewitness" \
    --no-prompt

# ================== SUMMARY ==================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "==================== SUMMARY ===================="
echo "Target Domain      : $DOMAIN"
echo "Total Subdomains   : ${TOTAL_SUBS:-0}"
echo "Resolved Domains   : ${TOTAL_RESOLVED:-0}"
echo "Live Hosts         : ${TOTAL_LIVE:-0}"
echo "Errors Encountered : $ERROR_COUNT"
echo "Execution Time     : ${DURATION}s"
echo "Log File           : $LOGFILE"
echo "================================================="

echo "[+] Recon complete. Report saved in $OUTDIR/"
```

Outputs are saved in recon-example.com/ with subfolders for passive/active/screenshots.

## Analysis Approach : 

The pipeline collects raw data, which is then used to:

- Identify live hosts and exposed services
- Detect technology stacks (via httpx)
- Prioritize endpoints for further testing
- Highlight potential risks such as:
  - exposed admin panels
  - unusual open ports
  - unvalidated endpoints

This bridges the gap between data collection and actionable insights.

## Example Observations : 

- Multiple subdomains resolved but did not respond to HTTP → potential internal services
- HTTP services detected without HTTPS → potential security risk
- Open ports identified via Nmap indicating exposed services
- Crawled endpoints revealed hidden paths not visible from main navigation

These observations would typically be used to guide deeper testing such as API validation, authentication testing, or fuzzing.

## 🌐 Proxychains Support
Some tools like subfinder, amass, and httpxgo are executed through proxychains to route traffic via configured SOCKS proxies or Tor for anonymized reconnaissance.

Make sure your proxy settings are correctly configured in `/etc/proxychains.conf`, and test with:

```bash
proxychains curl https://ifconfig.me
```
To disable proxying, comment out or remove proxychains from the relevant lines in recon.sh.

## 🛠️ Prerequisites
Make sure these tools are installed and available in $PATH. Use apt, go install, or your package manager of choice to install them.


## Notes
Wordlist path is hardcoded to /usr/share/wordlists/dirb/common.txt. Adjust as needed.

Eyewitness assumes GUI dependencies (e.g., for Kali Linux).



## Relevance to QA / Automation

This project demonstrates:

- Structured workflow execution
- Data collection and validation across multiple systems
- Identification of inconsistencies and unexpected behavior
- Understanding of system interactions and dependencies

These skills directly apply to:
- API testing and validation
- automation workflow monitoring
- incident investigation and root cause analysis

httpxgo can be swapped with httpx if you use the regular build.

