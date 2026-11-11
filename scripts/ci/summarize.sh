#!/usr/bin/env bash
# Print the suites, test counts and failures of an .xcresult (also to the job summary on CI).
#
#   scripts/ci/summarize.sh build/unit-iphone.xcresult
#
# Informational: the test step's own exit status decides pass/fail. Exits 0 when the
# bundle is missing (the build failed before tests ran; see the test step's log).
set -euo pipefail

result="${1:?usage: summarize.sh <path.xcresult>}"
if [[ ! -d "$result" ]]; then
  echo "summarize: $result does not exist (the build or test run failed before producing results)"
  exit 0
fi

if ! summary_json="$(xcrun xcresulttool get test-results summary --path "$result" --compact 2>/dev/null)" ||
   ! tests_json="$(xcrun xcresulttool get test-results tests --path "$result" --compact 2>/dev/null)"; then
  echo "summarize: $result is incomplete (the run was stopped before it finished writing results)"
  exit 0
fi

SUMMARY_JSON="$summary_json" TESTS_JSON="$tests_json" python3 - "$result" <<'PY' | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
import json, os, sys

summary = json.loads(os.environ["SUMMARY_JSON"])
tree = json.loads(os.environ["TESTS_JSON"])
name = os.path.basename(sys.argv[1])

def cases(node):
    if node.get("nodeType") == "Test Case":
        yield node
        return
    for child in node.get("children", []) or []:
        yield from cases(child)

def counts(node):
    c = {"Passed": 0, "Failed": 0, "Skipped": 0, "Expected Failure": 0}
    for case in cases(node):
        c[case.get("result", "Passed")] = c.get(case.get("result", "Passed"), 0) + 1
    return c

rows = []
def walk(node, bundle=None):
    kind = node.get("nodeType")
    if kind in ("Unit test bundle", "UI test bundle"):
        bundle = node.get("name")
        rows.append((bundle, "", counts(node)))
    elif kind == "Test Suite" and bundle:
        rows.append((bundle, node.get("name", ""), counts(node)))
        return
    for child in node.get("children", []) or []:
        walk(child, bundle)

for root in tree.get("testNodes", []):
    walk(root)

print(f"### Test summary: {name}\n")
print(f"Result: **{summary.get('result', '?')}**, "
      f"{summary.get('totalTestCount', 0)} tests: {summary.get('passedTests', 0)} passed, "
      f"{summary.get('failedTests', 0)} failed, {summary.get('skippedTests', 0)} skipped, "
      f"{summary.get('expectedFailures', 0)} expected failures\n")
print("| Bundle | Suite | Passed | Failed | Skipped |")
print("|---|---|---:|---:|---:|")
for bundle, suite, c in rows:
    print(f"| {bundle} | {suite or '(all)'} | {c['Passed']} | {c['Failed']} | {c['Skipped']} |")
failures = summary.get("testFailures", []) or []
if failures:
    print("\n#### Failures\n")
    for f in failures:
        text = (f.get("failureText") or "").replace("\n", " ")
        print(f"- `{f.get('targetName', '?')}` / `{f.get('testIdentifierString') or f.get('testName')}`: {text}")
print()
PY
