require "rubygems"
require "bundler/setup"
require "bundler/gem_tasks"
require "appraisal"
require "rspec/core/rake_task"

task(:default).clear
task default: :spec

if defined? RSpec
  task(:spec).clear
  RSpec::Core::RakeTask.new(:spec) do |t|
    t.verbose = false

    if defined?(JRUBY_VERSION)
      t.ruby_opts = ["--dev", "--debug"]
    end
  end
end

if !ENV["APPRAISAL_INITIALIZED"] && !ENV["TRAVIS"]
  task default: :appraisal
end
