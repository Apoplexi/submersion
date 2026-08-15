#!/usr/bin/env ruby
# frozen_string_literal: true

# Tests the App Review submission guard in the platform Fastfiles without
# booting fastlane or talking to App Store Connect. Each Fastfile is loaded
# against stubs for the fastlane DSL methods it calls at load time, which
# leaves the helper methods defined at top level where they can be exercised
# directly. Same approach as fastlane_beta_changelog_test.rb.
#
# What these guard, from promotion run 31903095751 (2026-08-15):
#
# The promote workflow submitted 1.7.4 while 1.7.3 was still with Apple. The
# old guard asked only "is THIS version already submitted?", so a different
# version sitting in review did not stop it. deliver then called
# Spaceship's ensure_version!, which finds the editable version and renames it
# in place when the version string differs. iOS 1.7.3 was WAITING_FOR_REVIEW,
# which IS an editable state, so the in-review submission was silently renamed
# to 1.7.4 while build 6027 stayed attached. The follow-up select_build was
# then refused ("The specified pre-release build could not be added"), leaving
# a submission labelled 1.7.4 carrying 1.7.3's binary.
#
# macOS failed differently in the same run only because Apple had advanced its
# copy to IN_REVIEW, which is NOT an editable state, so deliver tried to create
# a version instead and got a clean error. The loud failure was luck; the same
# defect produced silent mislabelling on the other platform.
#
# The decision under test is therefore version-agnostic: ANY review in progress
# for the platform blocks submission, whatever version it covers.

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

LANES = {}
def lane(name, &block)
  LANES[name] = block
end

# Platform blocks are yielded so the `def`s inside them land at top level.
def platform(_name)
  yield
end

# --- The cases, run against whichever Fastfile is currently loaded -----------

def assert_guard_behaviour(label)
  # 1. The iOS failure: a DIFFERENT version is in review. This is the case the
  #    old guard let through, and the one that corrupted the submission.
  reason = submission_skip_reason(
    app_version: '1.7.4',
    review_in_progress: true,
    review_version: '1.7.3',
  )
  check(!reason.nil?,
        "#{label}: a review in progress for 1.7.3 did not block submitting 1.7.4")
  check(reason.to_s.include?('1.7.3'),
        "#{label}: the skip reason did not name the version holding the review " \
        "(got #{reason.inspect}); the CI log has to say what to go look at")

  # 2. The macOS failure: same block, but Apple's submission record did not
  #    tell us which version it covers. Absence of a version string must not
  #    downgrade this to "proceed".
  reason = submission_skip_reason(
    app_version: '1.7.4',
    review_in_progress: true,
    review_version: nil,
  )
  check(!reason.nil?,
        "#{label}: a review in progress with an unknown version did not block")

  # 3. Same version already handed over. Belt and braces with case 1: this is
  #    the path a straight re-dispatch takes.
  reason = submission_skip_reason(
    app_version: '1.7.4',
    review_in_progress: false,
    edit_version: '1.7.4',
    edit_state: 'WAITING_FOR_REVIEW',
  )
  check(!reason.nil?,
        "#{label}: re-submitting a version already WAITING_FOR_REVIEW was allowed")

  # 4. The recovery state from that same incident: the submission was pulled,
  #    leaving DEVELOPER_REJECTED. That is editable and is exactly what this
  #    lane exists to submit, so it must proceed.
  reason = submission_skip_reason(
    app_version: '1.7.4',
    review_in_progress: false,
    edit_version: '1.7.4',
    edit_state: 'DEVELOPER_REJECTED',
  )
  check(reason.nil?,
        "#{label}: DEVELOPER_REJECTED was treated as blocking (got #{reason.inspect}); " \
        'a pulled submission is the lane\'s job to resubmit')

  # 5. macOS recovery: an editable version still carrying the OLD version
  #    string. deliver renames it in place, which is legitimate and is how
  #    macOS 1.7.3 became 1.7.4. Blocking here would strand the release.
  reason = submission_skip_reason(
    app_version: '1.7.4',
    review_in_progress: false,
    edit_version: '1.7.3',
    edit_state: 'DEVELOPER_REJECTED',
  )
  check(reason.nil?,
        "#{label}: an editable 1.7.3 blocked submitting 1.7.4 (got #{reason.inspect}); " \
        'renaming an editable version is how the rename-forward recovery works')

  # 6. Nothing in flight at all: the ordinary first submission of a version.
  reason = submission_skip_reason(
    app_version: '1.7.4',
    review_in_progress: false,
  )
  check(reason.nil?,
        "#{label}: a clean slate was blocked (got #{reason.inspect})")

  # 7. Regression guard on the obvious over-correction. A published app ALWAYS
  #    has a live version sitting in READY_FOR_SALE / READY_FOR_DISTRIBUTION.
  #    If those ever count as blocking, every promotion silently no-ops and the
  #    app can never ship again - a worse failure than the one being fixed.
  ['READY_FOR_SALE', 'READY_FOR_DISTRIBUTION', 'REPLACED_WITH_NEW_VERSION'].each do |live|
    reason = submission_skip_reason(
      app_version: '1.7.4',
      review_in_progress: false,
      edit_version: '1.7.3',
      edit_state: live,
    )
    check(reason.nil?,
          "#{label}: the live version state #{live} was treated as blocking " \
          "(got #{reason.inspect}); that would stop every future release")
  end
end

# --- Both platform Fastfiles ------------------------------------------------
# Loaded one at a time: the second load redefines the helper at top level, so
# testing after each load is what actually exercises both copies. These files
# are meant to stay in lockstep, and this is what catches them drifting.

# The two Apple Fastfiles are deliberate near-duplicates, so the second load
# redefines constants and methods the first already set. Ruby warns on both,
# and a dozen expected warnings is exactly how an unexpected one gets missed.
# Scoped to the load itself so anything the checks emit still surfaces.
def load_fastfile(*parts)
  previous = $VERBOSE
  $VERBOSE = nil
  load File.join(ROOT, *parts)
ensure
  $VERBOSE = previous
end

load_fastfile('ios', 'fastlane', 'Fastfile')
assert_guard_behaviour('ios')

load_fastfile('macos', 'fastlane', 'Fastfile')
assert_guard_behaviour('macos')

# --- Report -----------------------------------------------------------------

if $failures.empty?
  puts 'PASS: all fastlane submit guard tests passed'
else
  $failures.each { |f| puts "FAIL: #{f}" }
  exit 1
end
