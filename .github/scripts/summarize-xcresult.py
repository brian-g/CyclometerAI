#!/usr/bin/env python3
"""Print the failing tests in an .xcresult bundle, with their assertion text.

Exists because a failing CI run used to be unreadable. `xcodebuild`'s console
output for a failure is the test's *name* and nothing else — the 2026-09-07 run
(#211) put three bare names in 14k lines of log with no expectation text, no
source location, and no way to tell a real failure from a simulator flake.

`xcresulttool get test-results tests` has all of it. The shape is a tree of
nodes, and the parts that matter are:

    Test Case (result: Failed)
      nodeIdentifier: "BLECSCIntegrationTests/connectDiscoversBatteryService()"
      children:
        Failure Message: "BLECSCClientTests.swift:936: Expectation failed: ..."

Usage: summarize-xcresult.py <bundle.xcresult>
"""

import json
import subprocess
import sys


def failed_cases(nodes):
    """Yield every failed Test Case in the tree, depth-first."""
    for node in nodes:
        if node.get("result") != "Failed":
            continue
        if node.get("nodeType") == "Test Case":
            yield node
        else:
            # Only suites/bundles recurse: a Test Case's children are its
            # failure messages, not more cases.
            yield from failed_cases(node.get("children", []))


def main():
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} <bundle.xcresult>")
    bundle = sys.argv[1]

    raw = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests",
         "--path", bundle, "--compact"],
        capture_output=True, text=True, check=True,
    ).stdout
    cases = list(failed_cases(json.loads(raw).get("testNodes", [])))

    if not cases:
        # A failed job with no failed test is itself the useful signal: it means
        # the build, the simulator, or the runner died rather than an assertion.
        print("No failed tests in the bundle — the failure was the build, "
              "the simulator, or the runner.")
        return

    print(f"{len(cases)} failing test{'s' if len(cases) != 1 else ''}:\n")
    for case in cases:
        print(case.get("nodeIdentifier") or case.get("name", "<unnamed>"))
        for child in case.get("children", []):
            if child.get("nodeType") == "Failure Message":
                print(f"    {child.get('name', '')}")
        print()


if __name__ == "__main__":
    main()
