# Okay we have read our xml feed in bash, and we aren't narcissists so
# we will use python for this next part
import sys
import xml.etree.ElementTree as ET # phone home
from email.utils import parsedate_to_datetime
from pathlib import Path
from urllib.request import urlopen
import re

# We shall pass the downloaded feed as the first argument
feed_file = sys.argv[1]   # controlling urges to use a semicolon

#Last run time if it exists (0)..(0)
last_run = int(sys.argv[2]) if sys.argv[2] else None
codename = sys.argv[3]
output_file = sys.argv[4]

tree = ET.parse(feed_file)
root = tree.getroot()

# NO repeats so we'll use a set.
source_packages = set()

# So we have these xml items and they have links to follow
# These links should in theory give us the packages affected
# and we can update packages, can't we?
for item in root.findall("channel/item"):
    title = item.findtext("title", default="")
    published = item.findtext("pubDate", default="")
    link = item.findtext("link", default="")

    #TIME to convert
    published_time = parsedate_to_datetime(published).timestamp()

    # Skip those notices that occur before we last ran
    if last_run is not None and published_time < last_run:
        continue

    # Download this advisory's HTML page.
    with urlopen(link, timeout=30) as response:
        page = response.read().decode("utf-8")

    # Extract release names from the advisory's release links.
    releases = re.findall(
        r'href="/security/notices\?release=([a-z0-9-]+)"',
        page,
    )

    if not releases:
        raise ValueError(f"No release links found in {link}")

    if codename not in releases:
        print(f"Skipping {title}: does not list {codename}")
        continue

    # Extract source package names from the package links.
    packages = re.findall(
        r'href="/security/cves\?package=([a-z0-9][a-z0-9+.-]*)"',
        page,
    )

    if not packages:
        raise ValueError(f"No source package links found in {link}")

    source_packages.update(packages)
    print(f"{title}: {', '.join(sorted(set(packages)))}")

# Write a separate file containing only package names, one per line.
Path(output_file).write_text(
    "".join(f"{package}\n" for package in sorted(source_packages)),
    encoding="utf-8",
)

print(f"Found {len(source_packages)} unique packages possibly needing updating")
