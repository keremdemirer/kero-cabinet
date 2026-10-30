# frozen_string_literal: true
require_relative 'geometry_test'
require 'minitest/autorun'
require 'uri'

module Sketchup
  def self.read_default(_section,key,fallback)
    return @preference_values[key] if @preference_values && @preference_values.key?(key)
    fallback
  end
  def self.write_default(_section,key,value)
    (@preference_values||={})[key]=value
    @price_saved=value if key=='sheet_prices_v1'
    @sheet_saved=value if key=='sheet_settings'
    true
  end
end
module UI
  class HtmlDialog
    STYLE_DIALOG=0
    attr_reader :html,:callbacks,:scripts
    def initialize(**_options);@callbacks={};@scripts=[];(@@dialogs||=[]) << self;end
    def self.dialogs;@@dialogs||=[];end
    def set_html(html);@html=html;end
    def add_action_callback(name,&block);@callbacks[name]=block;end
    def set_on_closed(&block);@closed=block;end
    def show;@visible=true;end
    def close;@visible=false;@closed.call if @closed;end
    def visible?;@visible;end
    def execute_script(script);@scripts << script;end
  end
  def self.messagebox(message);raise message;end
  def self.openURL(url);@opened_url=url;end
  def self.opened_url;@opened_url;end
end

class SheetDialogTest < Minitest::Test
  def setup
    KeroCabinet.close_editors_for_reload
    Sketchup.instance_variable_set(:@sheet_saved,nil)
    Sketchup.instance_variable_set(:@price_saved,nil)
    Sketchup.instance_variable_set(:@preference_values,{})
    @rows=[{width:500,length:700,quantity:2,thickness:18,material:'18 mm Sheet',names:['Panel']}]
  end
  def test_command_prompts_first_then_generates_layout_and_print_snapshot
    KeroCabinet.stub(:cutlist_rows,@rows) { KeroCabinet.show_cutlist(:all) }
    setup=UI::HtmlDialog.dialogs.last
    assert_includes setup.html,'Sheet settings'
    refute_includes setup.html,'<table>'
    setup.callbacks['generate_layout'].call(nil,JSON.generate(KeroCabinet.sheet_defaults))
    report=UI::HtmlDialog.dialogs.last
    refute_same setup,report
    refute setup.visible?
    assert report.visible?
    assert_includes report.html,'Usage by thickness'
    assert_includes report.html,'Sheet 1 placement'
    assert_includes report.html,'2 pieces'
    assert report.callbacks.key?('sheet_settings')
    Dir.mktmpdir do |directory|
      Dir.stub(:tmpdir,directory) { report.callbacks['print_report'].call(nil) }
      path=URI::DEFAULT_PARSER.unescape(UI.opened_url.sub('file://',''))
      html=File.read(path)
      assert_includes html,'Usage by thickness'
      assert_includes html,'Sheet 1 placement'
      assert_includes html,'window.print()'
      refute_includes html,'window.sketchup.'
    end
  end
  def test_invalid_settings_stay_in_prompt_and_cancel_creates_no_report
    KeroCabinet.show_sheet_setup(@rows,:selected)
    dialog=UI::HtmlDialog.dialogs.last
    count=UI::HtmlDialog.dialogs.length
    dialog.callbacks['generate_layout'].call(nil,JSON.generate(KeroCabinet.sheet_defaults.merge('width'=>0)))
    assert_equal count,UI::HtmlDialog.dialogs.length
    assert dialog.visible?
    assert_includes dialog.scripts.last,'sheetError'
    dialog.callbacks['cancel_setup'].call(nil)
    refute dialog.visible?
    assert_equal count,UI::HtmlDialog.dialogs.length
    assert_nil Sketchup.instance_variable_get(:@sheet_saved)
  end
end
