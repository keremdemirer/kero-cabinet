# frozen_string_literal: true
require_relative 'geometry_test'
require 'minitest/autorun'

module UI
  class ReloadMenu
    attr_reader :items
    def initialize
      @items = []
    end
    def add_item(label, &block)
      @items << [label, block]
    end
  end
  def self.menu(_name)
    @reload_menu ||= ReloadMenu.new
  end
end

class ReloadTest < Minitest::Test
  U = KeroCabinet::Updater
  class Editor
    attr_reader :closed
    def close
      @closed = true
    end
  end

  def setup
    U.instance_variable_set(:@busy, false)
    U.instance_variable_set(:@restart_required, false)
    KeroCabinet.instance_variable_set(:@dialogs, [])
  end

  def test_repeated_reload_preserves_module_callbacks_model_and_single_menu
    original_module = KeroCabinet
    callback = KeroCabinet.module_eval { proc { clone_defaults } }
    model = Sketchup.active_model
    definition_count = model.definitions.all.length
    editor = Editor.new
    KeroCabinet.instance_variable_set(:@dialogs, [editor])
    assert U.reload_plugin('0.9.0')
    registered_count = UI.menu('Plugins').items.length
    assert U.reload_plugin('0.9.0')
    assert_same original_module, KeroCabinet
    assert editor.closed
    assert_empty KeroCabinet.instance_variable_get(:@dialogs)
    assert_equal KeroCabinet.clone_defaults, callback.call
    assert_equal definition_count, model.definitions.all.length
    assert_equal registered_count, UI.menu('Plugins').items.length
    refute U.instance_variable_get(:@restart_required)
  end

  def test_failed_load_is_reported_as_restart_fallback
    Kernel.stub(:load, lambda { |_path| raise SyntaxError, 'simulated invalid update' }) do
      error = assert_raises(U::UpdateError) { U.reload_plugin }
      assert_includes error.message, 'live reload failed'
      assert U.instance_variable_get(:@restart_required)
    end
  end

  def test_transition_from_old_core_without_close_helper
    old = KeroCabinet.instance_method(:close_editors_for_reload)
    KeroCabinet.send(:remove_method, :close_editors_for_reload)
    editor = Editor.new
    KeroCabinet.instance_variable_set(:@dialogs, [editor])
    assert U.reload_plugin('0.9.0')
    assert editor.closed
  ensure
    KeroCabinet.send(:define_method, :close_editors_for_reload, old) unless KeroCabinet.respond_to?(:close_editors_for_reload)
  end
end
