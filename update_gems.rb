#!/usr/bin/env ruby

require 'logger'
require 'singleton'
require 'net/http'
require 'json'

Project = Struct.new(:github_repo, :update_limit, :path, :groups)

class Config
  attr_accessor :github_token, :projects

  def initialize(github_token:, projects:)
    @github_token = github_token

    @projects = projects.split(' ').map! do |project_string|
      repo, update_limit, path, groups = project_string.split ':'
      Project.new(
        repo,
        (update_limit || 2).to_i,
        (path || '.'),
        groups&.split(','))
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
  def initialize(project)
    @repo = project.github_repo
    @path = project.path
    @update_limit = project.update_limit
    @groups = project.groups
  end

  def update_gems
    Log.info "updating repo #{repo}"
    RepoFetcher.new(repo).in_repo do
      update_multiple_gems_with_pr
    end
  end

  private

    attr_reader :repo, :path, :update_limit, :groups

    def outdated_gems
      return @outdated_gems unless @outdated_gems.nil?
      Log.debug "cd #{path}"
      gems = nil
      Dir.chdir(path) do
        Command.run 'bundle install', rbenv: true
        gems = Outdated.outdated_gems groups
      end
      Log.debug "back in #{`pwd`}"
      @outdated_gems = gems.take update_limit
    end

    def update_multiple_gems_with_pr
      Git.delete_branch update_branch
      Git.change_branch update_branch do
        outdated_gems.each do |gem_stats|
          update_single_gem gem_stats
        end
        Git.push
        sleep 2 # GitHub needs some time ;)
        Log.debug "cd #{path}"
        description =
          pr_description outdated_gems.map { |gem_stats| gem_stats[:gem] }
        Git.pull_request(
          "[GemUpdater]#{path != '.' ? "[" + path + "]" : ""} update gems\n\n" +
          description
        )
      end
    end

    def update_branch
      path_infix =
        if path == '.'
          ''
        else
          "_#{path}"
        end
      groups_infix = groups.to_a.reduce { |group| "_#{group}"}
      "update#{path_infix}#{groups_infix}_gems"
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
    def outdated_gems(groups)
      (
        outdated('patch', groups) +
        outdated('minor', groups) +
        outdated('major', groups)
      ).uniq { |gem_stats| gem_stats[:gem] }
    end

    def outdated(segment, groups)
      group_option =
        if groups.nil?
          ''
        else
          " --with='#{groups.join(' ')}'"
        end
      segment_option =
        if segment.nil?
          ''
        else
          " --#{segment}"
        end
      output =
        Command.run(
          "bundle outdated#{group_option}#{segment_option}",
          approve_exitcode: false, rbenv: true)
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
      GemUpdater.new(project).update_gems
    end
  end
  Log.debug "back in #{`pwd`}"
end

if $PROGRAM_NAME == __FILE__
  ENV['PROJECTS'] || puts('please provide PROJECTS to update')
  ENV['GITHUB_TOKEN'] || puts('please provide GITHUB_TOKEN')

  Configuration = Config.new(
    github_token: ENV['GITHUB_TOKEN'],
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
