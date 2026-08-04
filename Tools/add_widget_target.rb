#!/usr/bin/env ruby
# Adds the RadioWidget app-extension target to RadioApp.xcodeproj.
# Idempotent: fully removes any previous RadioWidget wiring first.
require 'xcodeproj'

project_path = File.expand_path('../RadioApp.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

app_target = project.targets.find { |t| t.name == 'RadioApp' }
raise 'App target not found' unless app_target

# --- clean any previous run ---------------------------------------------------
# 1. dependencies on the widget (or dangling)
app_target.dependencies.dup.each do |dep|
  if dep.target.nil? || (dep.target.respond_to?(:name) && dep.target.name == 'RadioWidget')
    app_target.dependencies.delete(dep)
    dep.remove_from_project
  end
end
# 2. embed phases
app_target.copy_files_build_phases.select { |ph| ph.name == 'Embed Foundation Extensions' }.each do |ph|
  app_target.build_phases.delete(ph)
  ph.remove_from_project
end
# 3. shared file already on the app target (avoid duplicate symbols on re-run)
app_target.source_build_phase.files.dup.each do |bf|
  if bf.file_ref.nil? || bf.display_name.to_s.include?('WidgetShared')
    app_target.source_build_phase.files.delete(bf)
    bf.remove_from_project
  end
end
# 4. the widget target itself
project.targets.select { |t| t.name == 'RadioWidget' }.each(&:remove_from_project)
# 5. groups + leftover product reference
['RadioWidget', 'Shared', 'WidgetResources'].each do |name|
  grp = project.main_group.children.find { |c| c.respond_to?(:display_name) && c.display_name == name }
  grp.remove_from_project if grp
end
project.products_group.children.dup.each do |ref|
  ref.remove_from_project if ref.respond_to?(:path) && ref.path.to_s.include?('RadioWidget.appex')
end

# --- create the widget target -------------------------------------------------
widget = project.new_target(:app_extension, 'RadioWidget', :ios, '26.5', nil, :swift)

# The gem auto-links Foundation.framework with a hardcoded (wrong) SDK path; drop it.
widget.frameworks_build_phase.files.dup.each do |bf|
  bf.remove_from_project if bf.display_name.to_s.include?('Foundation')
end

widget.build_configurations.each do |config|
  bs = config.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = 'Altamirano.RadioApp.RadioWidget'
  bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
  bs['INFOPLIST_FILE'] = 'RadioWidget/Info.plist'
  bs['GENERATE_INFOPLIST_FILE'] = 'NO'
  bs['CODE_SIGN_ENTITLEMENTS'] = 'RadioWidget/RadioWidget.entitlements'
  bs['CODE_SIGN_STYLE'] = 'Automatic'
  bs['DEVELOPMENT_TEAM'] = 'JKMR84FU58'
  bs['IPHONEOS_DEPLOYMENT_TARGET'] = '26.5'
  bs['SWIFT_VERSION'] = '5.0'
  bs['TARGETED_DEVICE_FAMILY'] = '1,2'
  bs['SKIP_INSTALL'] = 'YES'
  bs['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  # Must match the app target's values — App Store Connect rejects a mismatch.
  bs['MARKETING_VERSION'] = '1.2'
  bs['CURRENT_PROJECT_VERSION'] = '2'
  bs['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

# --- source files (group path is the folder; refs are bare filenames) ---------
widget_group = project.main_group.new_group('RadioWidget', 'RadioWidget')
%w[RadioWidgetBundle.swift NowPlayingWidget.swift QuickStationsWidget.swift WidgetTheme.swift].each do |f|
  widget.add_file_references([widget_group.new_reference(f)])
end

# shared model — compiled into BOTH targets
shared_group = project.main_group.new_group('Shared', 'Shared')
shared_ref = shared_group.new_reference('WidgetShared.swift')
widget.add_file_references([shared_ref])
app_target.add_file_references([shared_ref])

# --- localized strings ---------------------------------------------------------
# An extension has its own bundle, so it cannot read the app's Localizable.strings.
# Reference the very same files (no copies to keep in sync) as a variant group and
# copy them into the widget's own bundle. Without this every widget string — and the
# titles on the widget's own edit screen — falls back to the Spanish `value:` default.
LANGS = %w[en es fr de pt].freeze
res_group = project.main_group.new_group('WidgetResources')
variant = res_group.new_variant_group('Localizable.strings')
LANGS.each do |lang|
  ref = variant.new_reference("RadioApp/Localization/#{lang}.lproj/Localizable.strings")
  ref.name = lang
end
widget.add_resources([variant])

# Privacy manifest — Apple evaluates each bundle on its own, so the extension needs its
# own copy in its own bundle (the app's does not cover it).
widget.add_resources([widget_group.new_reference('PrivacyInfo.xcprivacy')])

# --- embed the extension in the app ------------------------------------------
app_target.add_dependency(widget)
embed = app_target.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
build_file = embed.add_file_reference(widget.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save
puts "OK: targets = #{project.targets.map(&:name).join(', ')}"
