#!/bin/zsh
set -euo pipefail

test_dir=${0:A:h}
app_root=${test_dir:h}
app_dir=$app_root/MarkdownApp
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/document-step5-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT

xcrun swiftc -parse-as-library \
  "$app_dir/Models/DocumentStorageMode.swift" \
  "$app_dir/Models/FileAccessCoordinator.swift" \
  "$app_dir/Models/DocumentMigrationJournal.swift" \
  "$app_dir/Models/DocumentRecoveryBackup.swift" \
  "$test_dir/DocumentMigrationJournalTests.swift" \
  -o "$output_dir/DocumentMigrationJournalTests"
"$output_dir/DocumentMigrationJournalTests"

xcrun swiftc -parse-as-library \
  "$app_dir/Models/DocumentActivityResolver.swift" \
  "$app_dir/Models/DocumentNode.swift" \
  "$app_dir/Models/DocumentTreeNode.swift" \
  "$app_dir/Models/DocumentStorageMode.swift" \
  "$app_dir/Models/FileAccessCoordinator.swift" \
  "$app_dir/Models/DocumentConflictURLFactory.swift" \
  "$app_dir/Models/DocumentLibraryService.swift" \
  "$app_dir/Models/FileStore.swift" \
  "$app_dir/Models/DocumentLibraryMergeService.swift" \
  "$test_dir/DocumentLibraryMergeTests.swift" \
  -o "$output_dir/DocumentLibraryMergeTests"
"$output_dir/DocumentLibraryMergeTests"

xcrun swiftc -parse-as-library \
  "$app_dir/Models/DocumentActivityResolver.swift" \
  "$app_dir/Models/DocumentNode.swift" \
  "$app_dir/Models/DocumentTreeNode.swift" \
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
  "$app_dir/Models/DocumentMigrationJournal.swift" \
  "$app_dir/Models/DocumentRecoveryBackup.swift" \
  "$app_dir/Models/DocumentLibraryMergeService.swift" \
  "$app_dir/Models/DocumentLibraryMigrationService.swift" \
  "$app_dir/Models/DocumentLibraryController.swift" \
  "$test_dir/DocumentEnableMigrationTests.swift" \
  -o "$output_dir/DocumentEnableMigrationTests"
"$output_dir/DocumentEnableMigrationTests"

print "DocumentMigrationStep5Tests: PASS"
