#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
app_root=${test_dir:h}
app_dir=$app_root/MarkdownApp
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/document-step4-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT

xcrun swiftc -parse-as-library \
  "$app_dir/Models/DocumentActivityResolver.swift" \
  "$app_dir/Models/DocumentNode.swift" \
  "$app_dir/Models/DocumentTreeNode.swift" \
  "$app_dir/Models/DocumentStorageMode.swift" \
  "$app_dir/Models/FileAccessCoordinator.swift" \
  "$app_dir/Models/DocumentLibraryService.swift" \
  "$app_dir/Models/FileStore.swift" \
  "$app_dir/Models/ICloudContainerService.swift" \
  "$app_dir/Models/ICloudLibraryPresenter.swift" \
  "$test_dir/ICloudRuntimeTests.swift" \
  -o "$output_dir/ICloudRuntimeTests"
"$output_dir/ICloudRuntimeTests"

entitlements=$app_dir/MarkdownApp.entitlements
plist=$app_root/Info.plist
project=$app_root/MarkdownApp.xcodeproj/project.pbxproj

plutil -lint "$entitlements" "$plist"
plutil -p "$entitlements" | rg -q 'iCloud.com.kvsur.MarkdownApp'
plutil -p "$entitlements" | rg -q 'CloudDocuments'
plutil -p "$plist" | rg -q 'NSUbiquitousContainerIsDocumentScopePublic.*true'
plutil -p "$plist" | rg -q 'NSUbiquitousContainerSupportedFolderLevels.*Any'
rg -q 'CODE_SIGN_ENTITLEMENTS = MarkdownApp/MarkdownApp.entitlements' "$project"
rg -q 'com.apple.iCloud' "$project"

print "ICloudCapabilityAudit: PASS"
