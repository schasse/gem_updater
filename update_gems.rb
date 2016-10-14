#!/usr/bin/env ruby

require 'logger'
require 'singleton'
require 'net/http'
require 'json'

GITHUB_TOKEN = ENV['GITHUB_TOKEN'] || puts('please provide GITHUB_TOKEN')
UPDATE_LIMIT = ENV['UPDATE_LIMIT'] || 2 # maximum number of gems to update
REPOSITORIES =
  (ENV['REPOSITORIES'] && ENV['REPOSITORIES'].split(' ')) ||
  puts('please provide REPOSITORIES to update')

raise 'missing configuration' if GITHUB_TOKEN.nil? || REPOSITORIES.nil?

class LoggerWrapper
  include Singleton

  attr_reader :logger

  def initialize
    @logger = Logger.new STDOUT
    if ENV['DEBUG'] || ENV['VERBOSE']
      @logger.level = Logger::DEBUG
    else
      @logger.level = Logger::INFO
    end
  end
end

def logger
  LoggerWrapper.instance.logger
end

class Command
  def self.run(command, approve_exitcode: false)
    logger.debug command
    output = `#{command} 2>&1`
    logger.debug output
    raise ScriptError, 'COMMAND FAILED!' if approve_exitcode && !$?.success?
    output
  end
end

class RepoFetcher
  attr_reader :repo

  def initialize(repo)
    fail 'not a correct repo format' unless repo =~ %r{\A\w+\/\w+\z}
    @repo = repo
  end

  def pull
    if File.exist? dir_name
      logger.info "repo #{repo} exists -> fetching remote"
      Dir.chdir(dir_name) do
        Command.run 'git fetch'
      end
    else
      logger.info "cloning repo #{repo}"
      Command.run "git clone git@github.com:#{repo}.git"
    end
  end

  private

    def dir_name
      repo.split('/').last
    end
end

class Git
  def self.setup
    Command.run 'git config --global user.email "gemupdater@gemupdater.com"'
    Command.run 'git config --global user.name gemupdater'
    Command.run 'git config --global'\
                " url.https://#{GITHUB_TOKEN}:x-oauth-basic@github.com/.insteadof"\
                ' git@github.com:'
  end

  def self.change_branch(branch)
    working_branch = current_branch
    if branch_exists? branch
      Command.run "git checkout #{branch}"
    else
      Command.run "git checkout -b #{branch}"
    end
    Git.push
    yield branch
    Command.run "git checkout #{working_branch}"
  end

  def self.branch_exists?(branch)
    system "git rev-parse --verify #{branch}"
  end

  def self.current_branch
    `git branch`.split("\n")
      .select { |line| line.start_with? '* ' }
      .first
      .gsub('* ', '')
  end

  def self.commit(message)
    Command.run 'git add .'
    Command.run "git commit -a -m '#{message}'"
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
end

GemUpdater = Struct.new(:repo) do
  def update_gems
    Dir.chdir(repo.split('/').last) do
      Command.run 'git checkout master'
      Git.pull
      Command.run 'bundle install'
      outdated_gems.take(UPDATE_LIMIT).each do |gem|
        update_single_gem gem
      end
    end
  end

  private

    def outdated_gems
      @outdated_gems ||=
        Command.run('bundle outdated --strict', approve_exitcode: false)
        .lines.map { |line| line.scan(/\ \ \*\ (\p{Graph}+)/) }
        .flatten.compact
    end

    def update_single_gem(gem)
      Git.change_branch "update_#{gem}" do
        logger.info "updating gem #{gem}"
        robust_master_merge
        Command.run "bundle update --source #{gem}"
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

Git.setup
REPOSITORIES.each do |repo|
  RepoFetcher.new(repo).pull
  GemUpdater.new(repo).update_gems
end
