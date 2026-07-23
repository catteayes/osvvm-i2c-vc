# File Name:         ci_regression.tcl
#
# Description:
#     CI regression driver for GitHub Actions (see .github/workflows/ci.yml).
#     Must be run with the current working directory set to a "sim" folder
#     one level below the repo root, matching OSVVM's usual convention (see
#     README "Building and running the regression") - all relative paths
#     below assume that.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0

source ../OsvvmLibraries/Scripts/StartUp.tcl

# Build the OSVVM base libraries (osvvm + Common, plus any reference VCs
# present as submodules). This is just compiling dependencies, not running
# the I2C regression, so ExitOnBuildDone is left at its default (false) here -
# a failure at this stage is caught explicitly instead.
if {[catch {build ../OsvvmLibraries/OsvvmLibraries.pro} errMsg]} {
  puts "ERROR: failed to build OsvvmLibraries: $errMsg"
  exit 1
}

# Now run the actual I2C VC regression. ExitOnBuildDone is turned on for this
# call only: OSVVM's own build procedure calls exit itself right when a build
# finishes if ExitOnBuildDone is true (0 on a clean pass, 1 if any test case
# failed) - which is what makes a failing test actually fail this CI step
# (and therefore show red on the PR) instead of silently exiting 0 regardless
# of test results.
set ::osvvm::ExitOnBuildDone true
build ../RunAllTests.pro
