require 'spec_helper'

Log = Logger.new '/dev/null'

RSpec.describe '#update_gems' do
  context 'with projects in repo' do
    before do
      Configuration =
        Config.new(
          github_token: 'test',
          update_limit: nil,
          repositories: 'schasse/outdated',
          projects: 'outdated:project_folder')
    end

    it 'pushes a new branch and creates a pr for the repository' do
      expect(Git).to receive(:push).once
      expect(Git).to receive(:pull_request).once
      update_gems
    end
  end

  context 'without projects in repo' do
    before do
      Configuration =
        Config.new(
          github_token: 'test',
          update_limit: nil,
          repositories: 'schasse/outdated',
          projects: nil)
    end

    it 'pushes a new branch and creates a pr for the repository' do
      expect(Git).to receive(:push).once
      expect(Git).to receive(:pull_request).once
      update_gems
    end
  end
end

RSpec.describe Outdated do
  before do
    Configuration =
      Config.new(
        github_token: 'test',
        update_limit: nil,
        repositories: 'schasse/outdated',
        projects: nil)
  end

  describe '#outdated_gems' do
    before do
      expect(Command)
        .to receive(:run).with('bundle outdated --patch', anything)
        .and_return <<~OUT
          Fetching gem metadata from https://rubygems.org/............
          Fetching version metadata from https://rubygems.org/.
          Resolving dependencies...

          Outdated gems included in the bundle:
            * domain_name (newest 0.5.20170404, installed 0.5.20161129)
            * dotenv (newest 2.1.2, installed 2.1.1) in groups "default"
            * puma (newest 3.7.1, installed 3.7.0) in groups "default"
            * rest-client (newest 2.0.2, installed 2.0.0)
            * tilt (newest 2.0.7, installed 2.0.6)
            * unf_ext (newest 0.0.7.4, installed 0.0.7.2)
OUT
      expect(Command)
        .to receive(:run).with('bundle outdated --minor', anything)
        .and_return <<~OUT
          Fetching gem metadata from https://rubygems.org/............
          Fetching version metadata from https://rubygems.org/.
          Resolving dependencies...

          Outdated gems included in the bundle:
            * bugsnag (newest 5.3.1, installed 5.2.0) in groups "default"
            * diff-lcs (newest 1.3, installed 1.2.5)
            * docker_registry2 (newest 0.6.0, installed 0.3.0) in groups "default"
            * domain_name (newest 0.5.20170404, installed 0.5.20161129)
            * dotenv (newest 2.2.0, installed 2.1.1) in groups "default"
            * puma (newest 3.8.2, installed 3.7.0) in groups "default"
            * rest-client (newest 2.0.2, installed 2.0.0)
            * tilt (newest 2.0.7, installed 2.0.6)
            * unf_ext (newest 0.0.7.4, installed 0.0.7.2)
OUT
      expect(Command)
        .to receive(:run).with('bundle outdated --major', anything)
        .and_return <<~OUT
          Fetching gem metadata from https://rubygems.org/............
          Fetching version metadata from https://rubygems.org/.
          Resolving dependencies...

          Outdated gems included in the bundle:
            * bugsnag (newest 5.3.1, installed 5.2.0) in groups "default"
            * diff-lcs (newest 1.3, installed 1.2.5)
            * docker_registry2 (newest 0.6.0, installed 0.3.0) in groups "default"
            * domain_name (newest 0.5.20170404, installed 0.5.20161129)
            * dotenv (newest 2.2.0, installed 2.1.1) in groups "default"
            * puma (newest 3.8.2, installed 3.7.0) in groups "default"
            * rest-client (newest 2.0.2, installed 2.0.0)
            * tilt (newest 2.0.7, installed 2.0.6)
            * unf_ext (newest 0.0.7.4, installed 0.0.7.2)
OUT
    end

    it 'sorts for the most important versions' do
      expect(Outdated.outdated_gems)
        .to eq [
              { gem: 'domain_name', segment: 'patch', outdated_level: 9275 },
              { gem: 'rest-client', segment: 'patch', outdated_level: 2 },
              { gem: 'unf_ext', segment: 'patch', outdated_level: 2 },
              { gem: 'dotenv', segment: 'patch', outdated_level: 1 },
              { gem: 'puma', segment: 'patch', outdated_level: 1 },
              { gem: 'tilt', segment: 'patch', outdated_level: 1 },
              { gem: 'docker_registry2', segment: 'minor', outdated_level: 30 },
              { gem: 'bugsnag', segment: 'minor', outdated_level: 11 },
              { gem: 'diff-lcs', segment: 'minor', outdated_level: -112 }
            ]

    end
  end

  describe '#outdated_level' do
    it 'calculates the correct level' do
      expect(Outdated.outdated_level '2.0.1', '2.0.0').to eq 1
      expect(Outdated.outdated_level '2.1.1', '2.0.0').to eq 11
    end
  end
end
