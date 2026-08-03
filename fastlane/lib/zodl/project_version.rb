# frozen_string_literal: true

module Zodl
  # Rewrites the version build settings in project.pbxproj.
  #
  # The project file is the single source of truth for both numbers: every
  # Info.plist reaches the build number through $(CURRENT_PROJECT_VERSION)
  # rather than holding a literal. `agvtool new-version -all` breaks that by
  # writing the number into each plist, which pins it where it silently wins
  # over the `CURRENT_PROJECT_VERSION=` xcarg the release lane passes to
  # override it. These functions touch nothing but the project file.
  module ProjectVersion
    MARKETING = /MARKETING_VERSION = [^;]+;/
    BUILD = /CURRENT_PROJECT_VERSION = [^;]+;/

    module_function

    def set_marketing_version(content, version)
      content.gsub(MARKETING, "MARKETING_VERSION = #{version};")
    end

    def set_build_number(content, build)
      content.gsub(BUILD, "CURRENT_PROJECT_VERSION = #{build};")
    end

    # Every configuration must end up on the same value; a partial rewrite means
    # variants would ship disagreeing numbers, which is how the 3.7.2/1.0 split
    # went unnoticed until a release reconciled against App Store Connect.
    def marketing_versions(content)
      content.scan(/MARKETING_VERSION = ([^;]+);/).flatten.map(&:strip).uniq
    end

    def build_numbers(content)
      content.scan(/CURRENT_PROJECT_VERSION = ([^;]+);/).flatten.map(&:strip).uniq
    end
  end
end
