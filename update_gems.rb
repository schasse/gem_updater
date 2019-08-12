#!/usr/bin/env ruby

require 'logger'
require 'singleton'
require 'net/http'
require 'json'

Project = Struct.new(:github_repo, :path)

class Config
  attr_accessor :github_token, :update_limit, :projects

  def initialize(github_token:, update_limit:, projects:)
    @github_token = github_token

    # maximum number of gems to update
    @update_limit =
      if update_limit.nil?
        2
      else
        update_limit.to_i
      end

    @projects = projects.split(' ').map! do |project_string|
      repo, path = project_string.split ':'
      Project.new repo, path
    end
  end
end

class Command
  def self.run(command, approve_exitcode: true, rbenv: false)
    Log.debug command
    output =
      if rbenv
        `bash -lc '#{command}' 2>&1`
      else
        `#{command} 2>&1`
      end
    if !$?.success? && approve_exitcode
      raise ScriptError, "COMMAND FAILED: #{command}\n#{output}"
    end
    Log.debug output
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
    dir = repo.split('/').last
    Log.debug "cd #{dir}"
    Dir.chdir(dir) do
      Command.run 'git checkout master'
      Git.pull
      yield
    end
    Log.debug "back in #{`pwd`}"
  end

  private

    def pull
      if File.exist? dir_name
        Log.debug "cd #{dir_name}"
        Dir.chdir(dir_name) do
          Command.run 'git fetch'
        end
        Log.debug "back in #{`pwd`}"
      else
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
    if Configuration.github_token
      Command.run 'git config --global'\
                  " url.https://#{Configuration.github_token}:x-oauth-basic@github.com/."\
                  'insteadof git@github.com:'
    else
      Command.run 'git config --global'\
                  ' url.https://github.com/.insteadof git@github.com:'
    end
  end

  def self.change_branch(branch)
    working_branch = current_branch
    Command.run "git checkout -b #{branch}"
    yield branch
    Command.run "git checkout #{working_branch}"
  end

  def self.delete_branch(branch)
    Command.run "git branch -D #{branch}", approve_exitcode: false
  end

  def self.current_branch
    Command.run('git rev-parse --abbrev-ref HEAD').strip
  end

  def self.commit(message)
    Command.run 'git add .'
    Command.run "git commit -a -m '#{message}'", approve_exitcode: false
  end

  def self.push
    Command.run(
      "git push origin #{current_branch} --force-with-lease",
      approve_exitcode: false)
  end

  def self.pull
    Command.run "git pull origin #{current_branch}"
  end

  def self.pull_request(message)
    Command.run(
      "GITHUB_TOKEN=#{Configuration.github_token} hub pull-request -m '#{message}'",
      approve_exitcode: false)
  end

  def self.checkout(branch, file)
    Command.run "git checkout #{branch} #{file}"
  end

  def self.clone_github(repo)
    Command.run "git clone git@github.com:#{repo}.git"
  end
end

class GemUpdater
  def initialize(repo, path)
    @repo = repo
    @path = path || '.'
  end

  def run_gems_update
    Log.debug "cd #{path}"
    outdated_gems = nil
    Dir.chdir(path) do
      Command.run 'bundle install', rbenv: true
      outdated_gems = Outdated.outdated_gems
    end
    Log.debug "back in #{`pwd`}"
    update_multiple_gems_with_pr outdated_gems
  end

  def update_gems
    Log.info "updating repo #{repo}"
    RepoFetcher.new(repo).in_repo do
      run_gems_update
    end
  end

  private

    attr_reader :repo, :path

    def update_multiple_gems_with_pr(outdated_gems)
      Git.delete_branch "update_#{path}_gems"
      Git.change_branch "update_#{path}_gems" do
        gems = outdated_gems.take(Configuration.update_limit)
        gems.each do |gem_stats|
          update_single_gem gem_stats
        end
        Git.push
        sleep 2 # GitHub needs some time ;)
        Log.debug "cd #{path}"
        description = pr_description gems.map { |gem_stats| gem_stats[:gem] }
        Git.pull_request(
          "[GemUpdater]#{path != '.' ? "[" + path + "]" : ""} update gems\n\n" +
          description
        )
      end
    end

    def update_single_gem(gem_stats)
      gem = gem_stats[:gem]
      segment = gem_stats[:segment]
      Log.info "updating gem #{gem}"
      Log.debug "cd #{path}"
      Dir.chdir(path) do
        Command.run "bundle update --#{segment} #{gem}", rbenv: true
        Git.commit "update #{gem}"
      end
      Log.debug "back in #{`pwd`}"
    end

    def pr_description(gems)
      gems.reduce('') do |string, gem|
        string + "\n* #{gem}: #{gem_uri(gem)} #{change_log(gem)}"
      end
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
      Log.debug "cd #{path}"
      from_version, to_version =
        Dir.chdir(path) do
          Command.run('git diff --word-diff=plain master Gemfile.lock')
            .scan(/^\ *#{gem}\ \[\-\((.+)\)\-\]\{\+\((.+)\)\+\}$/).first
        end
      Log.debug "back in #{`pwd`}"
      "#{gem_uri(gem)}/compare/v#{from_version}...v#{to_version} or " +
        "#{gem_uri(gem)}/compare/#{from_version}...#{to_version}"
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
          Command.run('bundle outdated', approve_exitcode: false, rbenv: true)
        else
          Command.run(
            "bundle outdated --#{segment}",
            approve_exitcode: false, rbenv: true)
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
  Log.debug "mkdir #{directory}"
  Dir.mkdir directory unless Dir.exist? directory
  Log.debug "cd #{directory}"
  Dir.chdir directory do
    Configuration.projects.each do |project|
      GemUpdater.new(project.github_repo, project.path).update_gems
    end
  end
  Log.debug "back in #{`pwd`}"
end

if $PROGRAM_NAME == __FILE__
  ENV['PROJECTS'] || ENV['REPOSITORIES'] || puts('please provide REPOSITORIES to update')
  ENV['GITHUB_TOKEN'] || puts('please provide GITHUB_TOKEN')

  Configuration = Config.new(
    github_token: ENV['GITHUB_TOKEN'],
    update_limit: ENV['UPDATE_LIMIT'],
    projects: ENV['PROJECTS'] || ENV['REPOSITORIES']
  )

  Log =
    if ENV['DEBUG'] || ENV['VERBOSE']
      Logger.new STDOUT
    else
      Logger.new(STDOUT).tap { |logger| logger.level = Logger::INFO }
    end

  update_gems
end
