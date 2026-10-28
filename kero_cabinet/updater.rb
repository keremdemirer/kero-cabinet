# frozen_string_literal: true
require 'net/http'
require 'openssl'
require 'json'
require 'base64'
require 'digest'
require 'fileutils'
require 'tmpdir'
require 'thread'

module KeroCabinet
  module Updater
    extend self
    REPOSITORY = 'keremdemirer/kero-cabinet'.freeze
    FILES = %w[kero_cabinet.rb kero_cabinet/core.rb kero_cabinet/updater.rb].freeze
    ROOT = File.expand_path('..', __dir__).freeze
    class UpdateError < StandardError; end

    def api(path)
      uri = URI("https://api.github.com/repos/#{REPOSITORY}/#{path}")
      request = Net::HTTP::Get.new(uri)
      request['Accept'] = 'application/vnd.github+json'
      request['User-Agent'] = 'Kero-Cabinet-Updater'
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = 10
      http.read_timeout = 20
      response = http.request(request)
      case response.code.to_i
      when 200
        raise UpdateError, 'GitHub response is too large.' if response.body.bytesize > 2_000_000
        JSON.parse(response.body)
      when 401, 404
        raise UpdateError, 'Repository access failed. Check that keremdemirer/kero-cabinet is public and available.'
      when 403, 429
        raise UpdateError, 'GitHub access was denied or the request limit was reached. Try again later.'
      else
        raise UpdateError, "GitHub request failed (HTTP #{response.code})."
      end
    end

    def content(path, ref)
      data = api("contents/#{path}?ref=#{ref}")
      unless data['type'] == 'file' && data['encoding'] == 'base64'
        raise UpdateError, "Invalid repository file: #{path}"
      end
      Base64.strict_decode64(data.fetch('content').delete("\n\r"))
    rescue KeyError, ArgumentError
      raise UpdateError, "Invalid repository file: #{path}"
    end

    def validate_manifest(value)
      valid = value.is_a?(Hash) && value['schema'] == 1 &&
        value['version'].is_a?(String) && value['version'].match?(/\A\d+\.\d+\.\d+\z/) &&
        value['files'].is_a?(Hash) && value['files'].keys.sort == FILES.sort &&
        value['files'].values.all? { |hash| hash.is_a?(String) && hash.match?(/\A[0-9a-f]{64}\z/) }
      raise UpdateError, 'Invalid update manifest. No files were changed.' unless valid
      value
    end

    def version_parts(version)
      version.split('.').map(&:to_i)
    end

    def find_update
      ref = api('git/ref/heads/main').dig('object', 'sha')
      raise UpdateError, 'Invalid repository revision.' unless ref.is_a?(String) && ref.match?(/\A[0-9a-f]{40}\z/)
      manifest = validate_manifest(JSON.parse(content('update.json', ref)))
      return nil unless (version_parts(manifest['version']) <=> version_parts(KeroCabinet::VERSION)) == 1
      { 'revision' => ref, 'manifest' => manifest }
    end

    def download(update)
      update.fetch('manifest').fetch('files').each_with_object({}) do |(path, digest), result|
        body = content(path, update.fetch('revision'))
        raise UpdateError, "Update checksum failed: #{path}. No files were changed." unless Digest::SHA256.hexdigest(body) == digest
        raise UpdateError, "Empty update file: #{path}" if body.empty?
        result[path] = body
      end
    end

    # Stage every file before replacement. Restore the previous set on failure.
    # All installed files are known paths; remote data cannot add arbitrary paths.
    def install(files, root = ROOT)
      raise UpdateError, 'Incomplete update.' unless files.keys.sort == FILES.sort
      FILES.each do |path|
        target = File.join(root, path)
        raise UpdateError, 'Symbolic link installations cannot be updated in place.' if File.symlink?(target) || File.symlink?(File.dirname(target))
      end
      Dir.mktmpdir('.kero-update-', root) do |stage|
        previous = {}
        changed = []
        FILES.each do |path|
          target = File.join(root, path)
          previous[path] = File.file?(target) ? File.binread(target) : nil
          staged = File.join(stage, path)
          FileUtils.mkdir_p(File.dirname(staged))
          File.binwrite(staged, files.fetch(path))
        end
        begin
          FILES.each do |path|
            changed << path
            replace_file(File.join(stage, path), File.join(root, path))
          end
        rescue StandardError
          changed.reverse_each do |path|
            target = File.join(root, path)
            if previous[path]
              File.binwrite(target, previous[path])
            else
              File.delete(target) if File.exist?(target)
            end
          end
          raise UpdateError, 'The update could not be installed. Previous files were restored. Check folder permissions.'
        end
      end
      true
    end

    def replace_file(source, target)
      File.rename(source, target)
    end

    # Background work never calls SketchUp APIs; the timer handles UI on its thread.
    def background(work, &complete)
      return UI.messagebox('An update operation is already running.') if @busy
      @busy = true
      queue = Queue.new
      Thread.new do
        begin
          queue << [:ok, work.call]
        rescue StandardError => error
          message = error.is_a?(UpdateError) ? error.message : 'The update request failed. Check your connection and try again.'
          queue << [:error, message]
        end
      end
      timer = UI.start_timer(0.2, true) do
        next if queue.empty?
        UI.stop_timer(timer)
        @busy = false
        status, result = queue.pop
        complete.call(status, result)
      end
    end

    def check(silent = false)
      return if @restart_required || @busy
      background(lambda { find_update }) do |status, update|
        if status == :error
          UI.messagebox(update) unless silent
        elsif update.nil?
          UI.messagebox("Kero Cabinet #{KeroCabinet::VERSION} is up to date.") unless silent
        else
          version = update['manifest']['version']
          answer = UI.messagebox("Kero Cabinet #{version} is available. Download and install it now?\n\nRestart SketchUp after installation to use the new version.", MB_YESNO)
          next unless answer == IDYES
          background(lambda { download(update) }) do |download_status, files|
            if download_status == :error
              UI.messagebox(files)
              next
            end
            begin
              install(files)
              @restart_required = true
              UI.messagebox("Kero Cabinet #{version} was installed. Save your work and restart SketchUp. No RBZ installation is needed.")
            rescue StandardError => error
              UI.messagebox(error.is_a?(UpdateError) ? error.message : 'Installation failed. Check folder permissions and try again.')
            end
          end
        end
      end
    rescue StandardError
      UI.messagebox('Could not check for updates. Try again later.') unless silent
    end

    def show_settings
      enabled = Sketchup.read_default('KeroCabinet', 'check_updates', true)
      answer = UI.inputbox(['Check for updates on startup'], [enabled ? 'Yes' : 'No'],
        ['Yes|No'], 'Kero Cabinet | Update settings')
      return unless answer
      Sketchup.write_default('KeroCabinet', 'check_updates', answer.first == 'Yes')
    end

    def startup_check
      return unless Sketchup.read_default('KeroCabinet', 'check_updates', true)
      # A repeating timer is stopped before any modal UI (including older SketchUp).
      timer = UI.start_timer(8, true) do
        UI.stop_timer(timer)
        check(true)
      end
    rescue StandardError
      nil
    end
  end
end
