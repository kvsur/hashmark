#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
app_root=${test_dir:h}
app_dir=$app_root/MarkdownApp
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/document-step6-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT

xcrun swiftc -parse-as-library \
  "$app_dir/Models/DocumentActivityResolver.swift" \
  "$app_dir/Models/DocumentNode.swift" \
  "$app_dir/Models/DocumentTreeNode.swift" \
  "$app_dir/Models/DocumentDraft.swift" \
  "$app_dir/Models/DocumentReferenceResolver.swift" \
  "$app_dir/Models/AIAttachment.swift" \
  "$app_dir/Models/DocumentStorageMode.swift" \
  "$app_dir/Models/DocumentStoragePreferenceStore.swift" \
  "$app_dir/Models/FileAccessCoordinator.swift" \
  "$app_dir/Models/DocumentConflictURLFactory.swift" \
  "$app_dir/Models/DocumentConflictResolver.swift" \
  "$app_dir/Models/DocumentLibraryService.swift" \
  "$app_dir/Models/FileStore.swift" \
  "$app_dir/Models/ICloudContainerService.swift" \
  "$app_dir/Models/ICloudLibraryPresenter.swift" \
  "$app_dir/Models/ICloudMetadataMonitor.swift" \
  "$app_dir/Models/OpenDocumentPresenter.swift" \
  "$app_dir/Models/DocumentMigrationJournal.swift" \
  "$app_dir/Models/DocumentRecoveryBackup.swift" \
  "$app_dir/Models/DocumentLibraryMergeService.swift" \
  "$app_dir/Models/DocumentLibraryMigrationService.swift" \
  "$app_dir/Models/DocumentLibraryController.swift" \
  "$test_dir/DocumentSynchronizationTests.swift" \
  -o "$output_dir/DocumentSynchronizationTests"
"$output_dir/DocumentSynchronizationTests"

print "DocumentSynchronizationStep6Tests: PASS"
