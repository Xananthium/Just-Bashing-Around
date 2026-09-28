# Just Bashing Around

I created this project for **26FA Linux Sys Admin (CIT-220-AC01)** with Professor Jay Powser.

I wanted to see whether I could automate part of the CVE and security-update process. I started with a Debian-targeted Bash script built around `debsecan`, but I ended up with a script that currently works only on my Ubuntu servers. I found it funny how just bashing around can lead me to so many places. As widens the wisdom, so narrows the path.

## Files

- I use `security_update.sh` to detect my Ubuntu release, download the Ubuntu Security Notices feed, compare affected source packages with my installed packages, and print a proposed `apt-get` upgrade command. I do not let the script install updates automatically.
- I use `process_xml.py` to parse the security feed, follow each relevant notice, and collect the affected source-package names for my Ubuntu release.

## How I Run It

I run this project on Ubuntu with Bash, `curl`, Python 3, `dpkg-query`, and an internet connection available.

```bash
chmod +x security_update.sh
./security_update.sh
```

I review the proposed upgrade command before I run any package updates myself. I also expect the script to create an `updates.log` file and a `lastrun` timestamp file in the project directory.
