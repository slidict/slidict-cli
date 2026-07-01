# frozen_string_literal: true

require_relative "lib/slidict/version"

Gem::Specification.new do |spec|
  spec.name = "slidict"
  spec.version = Slidict::VERSION
  spec.authors = ["Yusuke Abe"]
  spec.email = ["255824173+abechan1@users.noreply.github.com"]

  spec.summary = "Generate presentation-ready slides from a simple conversation."
  spec.description = "Slidict is a Ruby CLI for turning rough ideas into presentation-ready Markdown slides."
  spec.homepage = "https://slidict.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/slidict/slidict-cli"
  spec.metadata["changelog_uri"] = "https://github.com/slidict/slidict-cli/releases"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "puma", ">= 6.0"
  spec.add_dependency "rackup", ">= 2.0"
  spec.add_dependency "sinatra", ">= 4.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
