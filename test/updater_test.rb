# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../kero_cabinet/updater'
module KeroCabinet
  VERSION = '0.3.0' unless const_defined?(:VERSION)
end

class UpdaterTest < Minitest::Test
  U = KeroCabinet::Updater
  REVISION = 'a' * 40

  def manifest(version = '0.3.1')
    { 'schema' => 1, 'version' => version,
      'files' => U::FILES.to_h { |path| [path, Digest::SHA256.hexdigest("new #{path}")] } }
  end

  def test_rejects_traversal_missing_extra_and_invalid_hashes
    values = [manifest.merge('schema' => 2), manifest.merge('version' => 'latest')]
    value = manifest; value['files']['../other.rb'] = 'a' * 64; values << value
    value = manifest; value['files'].delete(U::FILES.first); values << value
    value = manifest; value['files'][U::FILES.first] = 'wrong'; values << value
    values.each { |item| assert_raises(U::UpdateError) { U.validate_manifest(item) } }
  end

  def test_only_newer_versions_are_offered_and_manifest_is_pinned
    ['0.2.9', '0.3.0', '0.3.1', '0.10.0'].each do |version|
      U.stub(:api, { 'object' => { 'sha' => REVISION } }) do
        U.stub(:content, lambda { |path, ref|
          assert_equal 'update.json', path
          assert_equal REVISION, ref
          JSON.generate(manifest(version))
        }) do
          result = U.find_update
          assert_equal(['0.3.1', '0.10.0'].include?(version), !result.nil?)
        end
      end
    end
  end

  def test_download_is_pinned_and_rejects_corruption
    update = { 'revision' => REVISION, 'manifest' => manifest }
    U.stub(:content, lambda { |path, ref|
      assert_equal REVISION, ref
      "new #{path}"
    }) { assert_equal U::FILES.sort, U.download(update).keys.sort }
    U.stub(:content, 'corrupt') { assert_raises(U::UpdateError) { U.download(update) } }
  end

  def with_installation
    Dir.mktmpdir do |root|
      U::FILES.each do |path|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.binwrite(File.join(root, path), "old #{path}")
      end
      yield root, U::FILES.to_h { |path| [path, "new #{path}"] }
    end
  end

  def test_install_and_stage_cleanup
    with_installation do |root, files|
      assert U.install(files, root)
      files.each { |path, value| assert_equal value, File.binread(File.join(root, path)) }
      assert_empty Dir.glob(File.join(root, '.kero-update-*'))
    end
  end

  def test_failed_replacement_rolls_back_every_changed_file
    with_installation do |root, files|
      count = 0
      U.stub(:replace_file, lambda { |source, target|
        count += 1
        raise IOError, 'simulated write failure' if count == 2
        File.rename(source, target)
      }) { assert_raises(U::UpdateError) { U.install(files, root) } }
      U::FILES.each { |path| assert_equal "old #{path}", File.binread(File.join(root, path)) }
      assert_empty Dir.glob(File.join(root, '.kero-update-*'))
    end
  end

  def test_incomplete_set_leaves_existing_files_untouched
    with_installation do |root, files|
      files.delete(U::FILES.last)
      assert_raises(U::UpdateError) { U.install(files, root) }
      U::FILES.each { |path| assert_equal "old #{path}", File.binread(File.join(root, path)) }
    end
  end

  def test_symbolic_link_is_rejected
    with_installation do |root, files|
      target = File.join(root, U::FILES.first)
      File.rename(target, target + '.original')
      File.symlink(target + '.original', target)
      assert_raises(U::UpdateError) { U.install(files, root) }
      assert_equal "old #{U::FILES.first}", File.binread(target + '.original')
    end
  end

  def test_authentication_errors_are_actionable_without_exposing_response_body
    response = Struct.new(:code, :body).new('404', 'private response content')
    http = Object.new
    class << http
      attr_accessor :use_ssl, :verify_mode, :open_timeout, :read_timeout
    end
    http.define_singleton_method(:request) { |_request| response }
    Net::HTTP.stub(:new, http) do
      error = assert_raises(U::UpdateError) { U.api('git/ref/heads/main') }
      assert_includes error.message, 'public'
      refute_includes error.message, 'private response content'
    end
  end
end

# A deterministic stand-in for SketchUp's asynchronous HTTP and timer APIs.
module Sketchup
  module Http
    class Request
      attr_accessor :headers
      attr_reader :url, :cancelled
      class << self
        attr_accessor :response, :pending, :start_result
      end
      def initialize(url)
        @url = url
      end
      def start(&callback)
        self.class.pending = callback
        callback.call(self, self.class.response) if self.class.response
        self.class.start_result != false
      end
      def cancel
        @cancelled = true
      end
    end
  end
end
module UI
  class << self
    attr_accessor :timers
    def start_timer(_delay, _repeat, &block)
      self.timers ||= {}
      id = (timers.keys.max || 0) + 1
      timers[id] = block
      id
    end
    def stop_timer(id)
      timers.delete(id)
    end
  end
end

class NativeUpdaterTest < Minitest::Test
  U = KeroCabinet::Updater
  Request = Sketchup::Http::Request
  Response = Struct.new(:status_code, :body)

  def setup
    UI.timers = {}
    Request.response = nil
    Request.start_result = true
    U.instance_variable_set(:@network_queue, nil)
    U.instance_variable_set(:@busy, false)
  end

  def test_native_success_retains_and_cleans_request
    Request.response = Response.new(200, '{"ok":true}')
    queue = Queue.new
    U.native_request('git/ref/heads/main', queue)
    assert_equal [:ok, { 'ok' => true }], queue.pop
    assert_empty U.instance_variable_get(:@requests)
    assert_empty UI.timers
  end

  def test_native_timeout_completes_once_and_ignores_late_callback
    queue = Queue.new
    U.native_request('git/ref/heads/main', queue)
    assert_equal 1, U.instance_variable_get(:@requests).length
    request = U.instance_variable_get(:@requests).first
    UI.timers.values.first.call
    status, error = queue.pop
    assert_equal :error, status
    assert_includes error.message, '40 seconds'
    assert request.cancelled
    Request.pending.call(request, Response.new(200, '{}'))
    assert queue.empty?
    assert_empty U.instance_variable_get(:@requests)
    assert_empty UI.timers
  end

  def test_start_failure_and_invalid_response_are_reported
    Request.start_result = false
    queue = Queue.new
    U.native_request('git/ref/heads/main', queue)
    assert_includes queue.pop[1].message, 'could not start'
    Request.start_result = true
    Request.response = Response.new(200, '<html>proxy login</html>')
    U.native_request('git/ref/heads/main', queue)
    assert_includes queue.pop[1].message, 'invalid response'
    assert_empty UI.timers
  end

  def test_background_dispatches_native_requests_and_releases_busy_state
    Request.response = Response.new(200, '{"native":true}')
    result = nil
    U.background(lambda { U.api('git/ref/heads/main') }) { |status, value| result = [status, value] }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    until result || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      UI.timers.values.dup.each(&:call)
      Thread.pass
    end
    assert_equal [:ok, { 'native' => true }], result
    refute U.instance_variable_get(:@busy)
    assert_nil U.instance_variable_get(:@network_queue)
  end

  def test_connection_errors_preserve_real_cause
    ssl = U.error_message(OpenSSL::SSL::SSLError.new('certificate verify failed'))
    assert_includes ssl, 'HTTPS'
    assert_includes ssl, 'certificate verify failed'
    assert_includes U.error_message(SocketError.new('lookup failed')), 'DNS'
    assert_includes U.error_message(Net::ReadTimeout.new), 'timed out'
    error = assert_raises(U::UpdateError) { U.parse_response(429, '{}') }
    assert_includes error.message, 'request limit'
    error = assert_raises(U::UpdateError) { U.parse_response(0, '') }
    assert_includes error.message, 'SketchUp'
  end
end
