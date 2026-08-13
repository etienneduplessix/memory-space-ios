#!/usr/bin/env ruby

require "xcodeproj"
require "fileutils"

project_root = File.expand_path("..", __dir__)
project_path = File.join(project_root, "MemorySpace.xcodeproj")
source_root = File.join(project_root, "MemorySpace")

FileUtils.rm_rf(project_path)
project = Xcodeproj::Project.new(project_path)
target = project.new_target(:application, "MemorySpace", :ios, "17.0")

target.product_name = "Memory Space"
target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.etienneduplessix.memoryspace"
  settings["PRODUCT_NAME"] = "Memory Space"
  settings["INFOPLIST_FILE"] = "MemorySpace/Supporting/Info.plist"
  settings["GENERATE_INFOPLIST_FILE"] = "NO"
  settings["IPHONEOS_DEPLOYMENT_TARGET"] = "17.0"
  settings["TARGETED_DEVICE_FAMILY"] = "1"
  settings["SWIFT_VERSION"] = "5.0"
  settings["SWIFT_STRICT_CONCURRENCY"] = "minimal"
  settings["CODE_SIGN_STYLE"] = "Automatic"
  settings["MARKETING_VERSION"] = "0.1.0"
  settings["CURRENT_PROJECT_VERSION"] = "1"
end

root_group = project.main_group.new_group("MemorySpace", "MemorySpace")
groups = { "" => root_group }

Dir.glob(File.join(source_root, "**", "*.swift")).sort.each do |file_path|
  relative_path = file_path.delete_prefix("#{source_root}/")
  components = relative_path.split("/")
  file_name = components.pop
  parent_key = ""

  components.each do |component|
    group_key = [parent_key, component].reject(&:empty?).join("/")
    groups[group_key] ||= groups[parent_key].new_group(component, component)
    parent_key = group_key
  end

  file_reference = groups[parent_key].new_file(file_name)
  target.add_file_references([file_reference])
end

supporting_group = groups[""].new_group("Supporting", "Supporting")
supporting_group.new_file("Info.plist")

[
  "AppIntents.framework",
  "AVFoundation.framework",
  "PhotosUI.framework",
  "Speech.framework",
  "SwiftData.framework",
  "SwiftUI.framework",
  "UIKit.framework",
  "Vision.framework"
].each do |framework|
  reference = project.frameworks_group.new_file("System/Library/Frameworks/#{framework}", "SDKROOT")
  target.frameworks_build_phase.add_file_reference(reference)
end

project.recreate_user_schemes
project.save
