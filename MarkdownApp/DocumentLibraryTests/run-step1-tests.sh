#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
app_root=${test_dir:h}
app_dir=$app_root/MarkdownApp
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/document-step1-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT

xcrun swiftc \
  "$app_dir/Models/DocumentActivityResolver.swift" \
  "$app_dir/Models/DocumentNode.swift" \
  "$app_dir/Models/DocumentTreeNode.swift" \
  "$app_dir/Models/DocumentStorageMode.swift" \
  "$app_dir/Models/FileAccessCoordinator.swift" \
  "$app_dir/Models/DocumentLibraryService.swift" \
  "$app_dir/Models/FileStore.swift" \
  "$app_root/FileBrowserTests/FileStoreRegressionTests.swift" \
  -o "$output_dir/FileStoreRegressionTests"
"$output_dir/FileStoreRegressionTests"

xcrun swiftc \
  "$app_dir/Models/DocumentActivityResolver.swift" \
  "$app_root/FileBrowserTests/DocumentActivityResolverTests.swift" \
  -o "$output_dir/DocumentActivityResolverTests"
"$output_dir/DocumentActivityResolverTests"

xcrun swiftc \
  "$app_dir/Models/AIAttachment.swift" \
  "$app_dir/Models/DocumentNode.swift" \
  "$app_dir/Models/DocumentTreeNode.swift" \
  "$app_dir/Models/DocumentDraft.swift" \
  "$app_dir/Models/DocumentRoute.swift" \
  "$app_dir/Models/MarkdownATXHeading.swift" \
  "$app_dir/Models/MarkdownDocumentTitleInference.swift" \
  "$app_dir/Models/ImportedDocument.swift" \
  "$app_dir/Models/DocumentReferenceResolver.swift" \
  "$app_dir/Features/Document/DocumentNamingState.swift" \
  "$app_dir/Features/Editor/Outline/MarkdownOutline.swift" \
  "$app_root/FileBrowserTests/DocumentBehaviorRegressionTests.swift" \
  -o "$output_dir/DocumentBehaviorRegressionTests"
"$output_dir/DocumentBehaviorRegressionTests"

xcrun swiftc -parse-as-library \
  "$test_dir/DocumentLibraryFaultInjectionTests.swift" \
  -o "$output_dir/DocumentLibraryFaultInjectionTests"
"$output_dir/DocumentLibraryFaultInjectionTests"
