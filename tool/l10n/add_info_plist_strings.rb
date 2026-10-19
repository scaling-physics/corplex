#!/usr/bin/env ruby
# Adds <app>/Runner/de.lproj/InfoPlist.strings (permission prompts, the Mac
# Services entry) to the iOS and macOS Runner targets as a localized
# resource, and "de" to each project's known regions. Idempotent; run it
# again after adding more languages' strings files:
#
#   GEM_HOME=~/.gem/ruby/2.6.0 ruby tool/l10n/add_info_plist_strings.rb
#
# Never edit the pbxproj by hand (see tool/ios/add_extensions.rb).
require 'xcodeproj'

LANGS = %w[de].freeze

%w[ios macos].each do |platform|
  path = File.expand_path("../../#{platform}/Runner.xcodeproj", __dir__)
  project = Xcodeproj::Project.open(path)
  target = project.targets.find { |t| t.name == 'Runner' } or abort "no Runner in #{platform}"
  group = project.main_group['Runner'] or abort "no Runner group in #{platform}"
  variant = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXVariantGroup) && c.name == 'InfoPlist.strings' }
  variant ||= group.new_variant_group('InfoPlist.strings')
  LANGS.each do |lang|
    next if variant.children.any? { |c| c.name == lang }
    ref = variant.new_reference("#{lang}.lproj/InfoPlist.strings")
    ref.name = lang
    ref.path = "#{lang}.lproj/InfoPlist.strings"
    ref.last_known_file_type = 'text.plist.strings'
  end
  unless target.resources_build_phase.files_references.include?(variant)
    target.resources_build_phase.add_file_reference(variant)
  end
  project.root_object.known_regions = (project.root_object.known_regions + LANGS).uniq
  project.save
  puts "#{platform}: ok"
end
