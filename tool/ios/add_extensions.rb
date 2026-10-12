#!/usr/bin/env ruby
# Adds the Share Extension and Widget Extension targets to ios/Runner.xcodeproj.
# Idempotent: targets that already exist are left alone. Re-run after
# `gem install --user-install xcodeproj`:
#
#   GEM_HOME=~/.gem/ruby/2.6.0 ruby tool/ios/add_extensions.rb
#
# Sources live in ios/ShareExtension and ios/CorplexWidget; App Group id is
# group.com.corplex.corplex (lib/features/platform/widget_data.dart).
require 'xcodeproj'

ROOT = File.expand_path('../../ios', __dir__)
APP_ID = 'com.corplex.corplex'
GROUP = 'group.com.corplex.corplex'
project = Xcodeproj::Project.open(File.join(ROOT, 'Runner.xcodeproj'))
runner = project.targets.find { |t| t.name == 'Runner' } or abort 'no Runner target'
deployment = runner.build_configurations.first.resolve_build_setting('IPHONEOS_DEPLOYMENT_TARGET') ||
             project.build_configurations.first.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] || '15.0'

def xcconfig_for(runner, name)
  runner.build_configurations.find { |c| c.name == name }&.base_configuration_reference
end

# Runner: entitlements.
runner.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
unless embed
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
end

def add_extension(project, runner, embed, name:, bundle_id:, sources:, plist:, entitlements:, deployment:)
  return if project.targets.any? { |t| t.name == name }
  target = project.new_target(:app_extension, name, :ios, deployment)
  group = project.main_group.new_group(name, name)
  sources.each { |s| target.source_build_phase.add_file_reference(group.new_reference(s)) }
  group.new_reference(plist)
  group.new_reference(entitlements)

  target.build_configurations.each do |c|
    s = c.build_settings
    s['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
    s['PRODUCT_NAME'] = '$(TARGET_NAME)'
    s['INFOPLIST_FILE'] = "#{name}/#{plist}"
    s['CODE_SIGN_ENTITLEMENTS'] = "#{name}/#{entitlements}"
    s['SWIFT_VERSION'] = '5.0'
    s['IPHONEOS_DEPLOYMENT_TARGET'] = deployment
    s['TARGETED_DEVICE_FAMILY'] = '1,2'
    s['SKIP_INSTALL'] = 'YES'
    s['CODE_SIGN_STYLE'] = 'Automatic'
    s['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
    s['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
    s['GENERATE_INFOPLIST_FILE'] = 'NO'
    s['CLANG_ENABLE_MODULES'] = 'YES'
    s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
    s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
    s['SWIFT_OPTIMIZATION_LEVEL'] = c.name == 'Debug' ? '-Onone' : '-O'
    if (x = xcconfig_for(runner, c.name))
      c.base_configuration_reference = x # for FLUTTER_BUILD_NAME / NUMBER
    end
  end

  runner.add_dependency(target)
  bf = embed.add_file_reference(target.product_reference, true)
  bf.settings = { 'ATTRIBUTES' => %w[RemoveHeadersOnCopy CodeSignOnCopy] }
end

add_extension(project, runner, embed,
  name: 'ShareExtension', bundle_id: "#{APP_ID}.ShareExtension",
  sources: ['ShareViewController.swift'], plist: 'Info.plist',
  entitlements: 'ShareExtension.entitlements', deployment: deployment)
add_extension(project, runner, embed,
  name: 'CorplexWidget', bundle_id: "#{APP_ID}.CorplexWidget",
  sources: ['CorplexWidget.swift'], plist: 'Info.plist',
  entitlements: 'CorplexWidget.entitlements', deployment: deployment)

# Runner/Runner.entitlements as a file reference (once).
runner_group = project.main_group['Runner']
unless runner_group.files.any? { |f| f.path == 'Runner.entitlements' }
  runner_group.new_reference('Runner.entitlements')
end

# Embed before the "Thin Binary" script phase, or Xcode reports a build cycle.
thin = runner.build_phases.index { |ph| ph.respond_to?(:name) && ph.name == 'Thin Binary' }
if thin && runner.build_phases.index(embed) > thin
  runner.build_phases.delete(embed)
  runner.build_phases.insert(thin, embed)
end

project.save

# Runner's Info.plist: URL schemes + AppGroupId (surgical text edit, once).
plist_path = File.join(ROOT, 'Runner/Info.plist')
plist = File.read(plist_path)
unless plist.include?('CFBundleURLTypes')
  block = <<-XML
	<key>AppGroupId</key>
	<string>#{GROUP}</string>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLName</key>
			<string>corplex</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>corplex</string>
			</array>
		</dict>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLName</key>
			<string>share-extension</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)</string>
			</array>
		</dict>
	</array>
  XML
  plist.sub!("\t<key>LSRequiresIPhoneOS</key>", block + "\t<key>LSRequiresIPhoneOS</key>") or abort 'plist anchor missing'
  File.write(plist_path, plist)
end
puts 'done'
