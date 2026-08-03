require "minitest/autorun"
require "zodl/project_version"

class ZodlProjectVersionTest < Minitest::Test
  # Two configurations, as the real project has, plus a plist-style reference to
  # prove the build setting is rewritten without touching the indirection.
  PBXPROJ = <<~PROJ
    				MARKETING_VERSION = 1.0;
    				CURRENT_PROJECT_VERSION = 3;
    				MARKETING_VERSION = 3.7.2;
    				CURRENT_PROJECT_VERSION = 3;
  PROJ

  def test_set_marketing_version_rewrites_every_configuration
    result = Zodl::ProjectVersion.set_marketing_version(PBXPROJ, "1.0.1")

    assert_equal ["1.0.1"], Zodl::ProjectVersion.marketing_versions(result)
  end

  def test_set_build_number_rewrites_every_configuration
    result = Zodl::ProjectVersion.set_build_number(PBXPROJ, 4)

    assert_equal ["4"], Zodl::ProjectVersion.build_numbers(result)
  end

  def test_setting_one_leaves_the_other_alone
    result = Zodl::ProjectVersion.set_build_number(PBXPROJ, 4)

    assert_equal %w[1.0 3.7.2], Zodl::ProjectVersion.marketing_versions(result)
  end

  # The regression this module exists for: the build number belongs in the
  # project, never written into an Info.plist as a literal.
  def test_build_number_indirection_is_preserved
    plist = <<~PLIST
      <key>CFBundleVersion</key>
      <string>$(CURRENT_PROJECT_VERSION)</string>
    PLIST

    refute_includes Zodl::ProjectVersion.set_build_number(plist, 4), "<string>4</string>"
    assert_includes Zodl::ProjectVersion.set_build_number(plist, 4), "$(CURRENT_PROJECT_VERSION)"
  end

  def test_reports_a_split_project_before_it_is_reconciled
    assert_equal %w[1.0 3.7.2], Zodl::ProjectVersion.marketing_versions(PBXPROJ)
  end
end
