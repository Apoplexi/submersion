#!/usr/bin/env ruby
# frozen_string_literal: true

# Tests the release-note helpers in the platform Fastfiles without booting
# fastlane. Each Fastfile is loaded against stubs for the handful of fastlane
# DSL methods it calls at load time, which leaves the helper methods defined at
# top level where they can be exercised directly.
#
# What these guard: the beta pipeline feeds "What to Test" from an environment
# variable. Ruby's `||` only falls back on nil, so a blank value would have been
# published verbatim, and a tester reads empty notes as "the previous build's
# notes still apply" - the confusion this whole change set exists to fix.

require 'fileutils'
require 'tmpdir'

ROOT = File.expand_path('../..', __dir__)

$failures = []

def check(condition, message)
  $failures << message unless condition
end

# --- Minimal fastlane DSL stubs ---------------------------------------------

module UI
  def self.important(_msg); end
  def self.message(_msg); end
  def self.success(_msg); end
  def self.user_error!(msg)
    raise ArgumentError, msg
  end
end

def default_platform(_name); end
def desc(_text); end

# Lane bodies are never run here, so the block is deliberately not yielded.
def lane(_name, &_block); end

# Platform blocks are yielded so the `def`s inside them land at top level.
def platform(_name)
  yield
end

def with_env(vars)
  previous = vars.keys.to_h { |k| [k, ENV[k]] }
  vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  yield
ensure
  previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
end

# --- TestFlight changelog (iOS Fastfile) ------------------------------------

load File.join(ROOT, 'ios', 'fastlane', 'Fastfile')

with_env('BETA_CHANGELOG' => nil) do
  check(!beta_changelog.to_s.strip.empty?, 'unset BETA_CHANGELOG produced blank notes')
end

with_env('BETA_CHANGELOG' => '') do
  check(!beta_changelog.to_s.strip.empty?, 'empty BETA_CHANGELOG produced blank notes')
end

with_env('BETA_CHANGELOG' => '   ') do
  check(!beta_changelog.to_s.strip.empty?, 'whitespace BETA_CHANGELOG produced blank notes')
end

with_env('BETA_CHANGELOG' => "New in this build\n- a real change") do
  check(beta_changelog.include?('a real change'), 'real notes were not passed through')
  check(beta_changelog.include?("\n"), 'multi-line notes were flattened')
end

with_env('BETA_CHANGELOG' => 'x' * 5000) do
  check(beta_changelog.length <= 4000,
        "notes were #{beta_changelog.length} chars, over Apple's 4000 limit")
end

with_env('BETA_CHANGELOG' => 'x' * 4000) do
  check(beta_changelog.length == 4000, 'notes exactly at the limit were altered')
end

# --- Play changelog (Android Fastfile) --------------------------------------

load File.join(ROOT, 'android', 'fastlane', 'Fastfile')

Dir.mktmpdir do |tmp|
  Dir.chdir(tmp) do
    changelog_path = lambda do |code|
      File.join(tmp, 'fastlane', 'metadata', 'android', 'en-US', 'changelogs', "#{code}.txt")
    end

    # Missing inputs must not write a file, and must report that the upload
    # should skip changelogs rather than blanking the notes already on Play.
    with_env('PLAY_BETA_CHANGELOG' => nil, 'PLAY_VERSION_CODE' => '123') do
      check(write_beta_changelog == false, 'missing notes did not disable changelog upload')
      check(!File.exist?(changelog_path.call(123)), 'missing notes still wrote a changelog file')
    end

    with_env('PLAY_BETA_CHANGELOG' => 'something', 'PLAY_VERSION_CODE' => nil) do
      check(write_beta_changelog == false, 'missing version code did not disable changelog upload')
    end

    with_env('PLAY_BETA_CHANGELOG' => '  ', 'PLAY_VERSION_CODE' => '123') do
      check(write_beta_changelog == false, 'blank notes did not disable changelog upload')
    end

    # A non-numeric version code would silently produce a file supply never
    # reads, so it fails loudly instead.
    with_env('PLAY_BETA_CHANGELOG' => 'notes', 'PLAY_VERSION_CODE' => 'v1.2.3') do
      raised = begin
        write_beta_changelog
        false
      rescue ArgumentError
        true
      end
      check(raised, 'a non-numeric PLAY_VERSION_CODE was accepted')
    end

    with_env('PLAY_BETA_CHANGELOG' => "New in this build\n- a real change",
             'PLAY_VERSION_CODE' => '5163') do
      check(write_beta_changelog == true, 'valid inputs did not enable changelog upload')
      written = File.read(changelog_path.call(5163))
      check(written.include?('a real change'), 'notes were not written to the changelog file')
    end

    with_env('PLAY_BETA_CHANGELOG' => 'y' * 900, 'PLAY_VERSION_CODE' => '5164') do
      write_beta_changelog
      written = File.read(changelog_path.call(5164))
      check(written.length <= 500,
            "Play changelog was #{written.length} chars, over Google's 500 limit")
    end
  end
end

# --- Report -----------------------------------------------------------------

if $failures.empty?
  puts 'PASS: all fastlane beta changelog tests passed'
else
  $failures.each { |f| puts "FAIL: #{f}" }
  exit 1
end
