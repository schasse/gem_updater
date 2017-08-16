#!/usr/bin/env ruby

require 'logger'
require 'singleton'
require 'net/http'
require 'json'

if ENV['GEMUPDATER_ENV'] != 'test'
    GITHUB_TOKEN = ENV['GITHUB_TOKEN'] || puts('please provide GITHUB_TOKEN')
    UPDATE_LIMIT = ENV['UPDATE_LIMIT'] || 2 # maximum number of gems to update
    REPOSITORIES =
      (ENV['REPOSITORIES'] && ENV['REPOSITORIES'].split(' ')) ||
      puts('please provide REPOSITORIES to update')

    raise 'missing configuration' if GITHUB_TOKEN.nil? || REPOSITORIES.nil?
else
  GITHUB_TOKEN = nil
  UPDATE_LIMIT = 2
  REPOSITORIES = ['schasse/outdated'].freeze
end

Log =
  if ENV['DEBUG'] || ENV['VERBOSE']
    Logger.new STDOUT
  else
    Logger.new(STDOUT).tap { |logger| logger.level = Logger::INFO }
  end

class Command
  def self.run(command, approve_exitcode: true)
    Log.debug command
    output = `#{command} 2>&1`
    Log.debug output
    raise ScriptError, 'COMMAND FAILED!' if approve_exitcode && !$?.success?
    output
  end
end

class RepoFetcher
  attr_reader :repo

  def initialize(repo)
    @repo = repo
  end

  def in_repo
    pull
    Dir.chdir(repo.split('/').last) do
      Command.run 'git checkout master'
      Git.pull
      yield
    end
  end

  private

    def pull
      if File.exist? dir_name
        Log.info "repo #{repo} exists -> fetching remote"
        Dir.chdir(dir_name) do
          Command.run 'git fetch'
        end
      else
        Log.info "cloning repo #{repo}"
        Git.clone_github repo
      end
    end

    def dir_name
      repo.split('/').last
    end
end

class Git
  def self.setup
    Command.run 'git config --global user.email "gemupdater@gemupdater.com"'
    Command.run 'git config --global user.name gemupdater'
    if GITHUB_TOKEN
      Command.run 'git config --global'\
                  " url.https://#{GITHUB_TOKEN}:x-oauth-basic@github.com/."\
                  'insteadof git@github.com:'
    else
      Command.run 'git config --global'\
                  ' url.https://github.com/.insteadof git@github.com:'
    end
  end

  def self.change_branch(branch)
    working_branch = current_branch
    if branch_exists? branch
      Command.run "git checkout #{branch}"
    else
      Command.run "git checkout -b #{branch}"
    end
    yield branch
    Command.run "git checkout #{working_branch}"
  end

  def self.branch_exists?(branch)
    system "git rev-parse --verify #{branch}"
  end

  def self.current_branch
    Command.run('git rev-parse --abbrev-ref HEAD').strip
  end

  def self.commit(message)
    Command.run 'git add .'
    Command.run "git commit -a -m '#{message}'", approve_exitcode: false
  end

  def self.push
    Command.run "git push origin #{current_branch}"
  end

  def self.pull
    Command.run "git pull origin #{current_branch}"
  end

  def self.merge(branch)
    Command.run "GIT_MERGE_AUTOEDIT=no git pull origin #{branch}"
  end

  def self.pull_request(message)
    Command.run "GITHUB_TOKEN=#{GITHUB_TOKEN} hub pull-request -m '#{message}'"
  end

  def self.checkout(branch, file)
    Command.run "git checkout #{branch} #{file}"
  end

  def self.clone_github(repo)
    Command.run "git clone git@github.com:#{repo}.git"
  end

  def self.reset
    Command.run 'git reset --hard'
  end
end

class GemUpdater
  def initialize(repo)
    @repo = repo
  end

  def update_gems
    RepoFetcher.new(repo).in_repo do
      Command.run 'bundle install'
      # update_ruby
      Outdated.outdated_gems.take(UPDATE_LIMIT).each do |gem_stats|
        update_single_gem gem_stats
      end
    end
  end

  private

    attr_reader :repo

    def update_ruby
      Git.change_branch 'update_ruby' do
        Log.info 'updating ruby version'
        robust_master_merge
        Command.run 'bundle update --ruby'
        Git.commit 'update ruby version'
        Git.push
        sleep 2 # GitHub needs some time ;)
        Git.pull_request('[GemUpdater] update ruby version')
      end
    end

    def update_single_gem(gem_stats)
      gem = gem_stats[:gem]
      segment = gem_stats[:segment]
      Git.change_branch "update_#{gem}" do
        Log.info "updating gem #{gem}"
        robust_master_merge
        Command.run "bundle update --#{segment} #{gem}"
        Git.commit "update #{gem}"
        Git.push
        sleep 2 # GitHub needs some time ;)
        Git.pull_request("[GemUpdater] update #{gem}\n\n"\
          "#{gem_uri(gem)}\n\n#{change_log(gem)}")
      end
    end

    def robust_master_merge
      Git.merge 'master'
    rescue ScriptError # merge conflicts...
      Git.checkout 'master', 'Gemfile.lock'
      Git.commit 'merge master'
    end

    def gem_uri(gem)
      info =
        JSON.parse(
          Net::HTTP.get(
            URI("https://rubygems.org/api/v1/gems/#{gem}.json")))
      info['source_code_uri'] || info['homepage_uri']
    rescue JSON::ParserError
      ''
    end

    def change_log(gem)
      from_version, to_version =
        Command.run('git diff --word-diff=plain master Gemfile.lock')
          .scan(/^\ *#{gem}\ \[\-\((.+)\)\-\]\{\+\((.+)\)\+\}$/).first
      gem_uri(gem) + "/compare/v#{from_version}...v#{to_version} or " +
        gem_uri(gem) + "/compare/#{from_version}...#{to_version}"
    end
end

class Outdated
  class << self
    def outdated_gems
      (outdated('patch') + outdated('minor') + outdated('major'))
        .uniq { |gem_stats| gem_stats[:gem] }
    end

    def outdated(segment)
      output =
        if segment.nil?
          Command.run('bundle outdated', approve_exitcode: false)
        else
          Command.run("bundle outdated --#{segment}", approve_exitcode: false)
        end
      output.lines.map do |line|
        regex = /\ \ \*\ (\p{Graph}+)\ \(newest\ ([\d\.]+)\,\ installed ([\d\.]+)/
        gem, newest, installed = line.scan(regex)&.first
        unless gem.nil?
          {
            gem: gem,
            segment: segment,
            outdated_level: outdated_level(newest, installed)
          }
        end
      end.compact.sort_by { |g| -g[:outdated_level] }
    end

    def outdated_level(newest, installed)
      new_int = newest.gsub('.', '').to_i
      installed_int = installed.gsub('.', '').to_i
      new_int - installed_int
    end
  end
end

def update_gems
  Git.setup
  directory = 'repositories_cache'
  Dir.mkdir directory unless Dir.exist? directory
  Dir.chdir directory do
    REPOSITORIES.each do |repo|
      GemUpdater.new(repo).update_gems
    end
  end
end

if $PROGRAM_NAME == __FILE__
  update_gems
end
