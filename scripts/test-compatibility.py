import argparse
import json
from pathlib import Path
import subprocess


parser = argparse.ArgumentParser(description="Run synthetic KeychainEditor regression tests.")
parser.add_argument("binary", type=Path)
args = parser.parse_args()
binary = str(args.binary.resolve())
subprocess.run([binary], check=True)
for scenario, expected_status, expected_count in [("empty", 0, 0), ("nil", 1, 0), ("partial", 1, 1)]:
    for search in [[], ["Synthetic Service"]]:
        result = subprocess.run([binary, scenario] + search, capture_output=True, text=True)
        assert result.returncode == expected_status, (scenario, result.stderr)
        items = json.loads(result.stdout)
        assert isinstance(items, list) and len(items) == expected_count, scenario
        assert bool(result.stderr) == bool(expected_status), scenario
        assert "Synthetic Data" not in result.stderr, "diagnostic disclosed data"
print("PASS: synthetic dump/search stdout, stderr, and exit status checks.")
