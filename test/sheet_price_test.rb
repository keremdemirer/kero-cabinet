# frozen_string_literal: true
require_relative 'sheet_dialog_test'

class SheetPriceTest < Minitest::Test
  def setup
    Sketchup.instance_variable_set(:@sheet_saved,nil)
    Sketchup.instance_variable_set(:@price_saved,nil)
    @rows=[{width:500,length:500,quantity:4,thickness:18,material:'18 mm Sheet',names:['Panel']},
      {width:500,length:500,quantity:1,thickness:18,material:'18 mm Plywood Sheet',names:['Other panel']}]
    @settings=KeroCabinet.sheet_defaults.merge('width'=>1000,'length'=>1000,'edge'=>0,'kerf'=>0)
    @key=KeroCabinet.sheet_price_profile('18 mm Sheet',18)
    @other=KeroCabinet.sheet_price_profile('18 mm Plywood Sheet',18)
  end
  def test_decimal_prices_are_exact_and_invalid_values_are_rejected
    assert_equal 125075,KeroCabinet.sheet_price_cents('1250,75')
    assert_equal 10,KeroCabinet.sheet_price_cents('0.1')
    assert_equal 0,KeroCabinet.sheet_price_cents('0')
    assert_nil KeroCabinet.sheet_price_cents(' ')
    assert_equal '1,250.75',KeroCabinet.sheet_money(125075)
    %w[-1 NaN Infinity 1.234 1,000.00 =12].each { |value| assert_raises(ArgumentError) { KeroCabinet.sheet_price_cents(value) } }
  end
  def test_cost_uses_whole_sheets_and_sums_distinct_material_rates
    plan=KeroCabinet.sheet_layout(@rows,@settings.merge('prices'=>{@key=>'1250.25',@other=>'2000.10'}))
    costs=plan[:groups].map { |g| KeroCabinet.sheet_group_cost(plan,g) }
    assert_equal 325035,costs.sum { |c| c[:total_cents] }
    summary=KeroCabinet.sheet_usage_summary(plan).first
    assert_equal 2,summary[:sheets]
    assert_equal 325035,summary[:cost_cents]
    assert_equal 0,summary[:unpriced_sheets]
    html=KeroCabinet.cutlist_html(@rows,:all,plan)
    assert_includes html,'3,250.35'
    assert_includes html,'Unit price'
    assert_includes html,'Total sheet cost'
    refute_includes html,'Known subtotal - INCOMPLETE'
  end
  def test_blank_price_is_not_free_and_oversized_parts_keep_cost_partial
    plan=KeroCabinet.sheet_layout(@rows,@settings.merge('prices'=>{@key=>'0'}))
    summary=KeroCabinet.sheet_usage_summary(plan).first
    assert_equal 1,summary[:unpriced_sheets]
    assert_equal 0,summary[:cost_cents]
    assert_includes KeroCabinet.sheet_cost_html(plan),'1 sheets have no unit price'
    oversized=@rows+[ @rows[0].merge(width:1500,length:2000,quantity:1) ]
    plan=KeroCabinet.sheet_layout(oversized,@settings.merge('prices'=>{@key=>'10',@other=>'0'}))
    html=KeroCabinet.sheet_cost_html(plan)
    assert_includes html,'Known subtotal - INCOMPLETE'
    assert_includes html,'1 oversized parts are not fitted or costed'
    assert_equal 1000,KeroCabinet.sheet_usage_summary(plan).first[:cost_cents]
  end
  def test_catalog_preserves_other_sizes_currencies_and_pending_edits
    settings=KeroCabinet.validate_sheet_settings(@settings.merge('prices'=>{@key=>'1250,25',@other=>''}))
    old_key=KeroCabinet.sheet_price_catalog_key('18 mm Sheet',18,settings.merge('width'=>2100,'length'=>2800))
    usd_key=KeroCabinet.sheet_price_catalog_key('18 mm Sheet',18,settings.merge('currency'=>'USD'))
    catalog={old_key=>'2200.00'}
    KeroCabinet.save_sheet_price_catalog(@rows,settings,catalog,{usd_key=>'45.50'})
    saved=KeroCabinet.read_sheet_price_catalog
    assert_equal '2200.00',saved[old_key]
    assert_equal '45.50',saved[usd_key]
    key=KeroCabinet.sheet_price_catalog_key('18 mm Sheet',18,settings)
    assert_equal '1250.25',saved[key]
    assert_equal key,KeroCabinet.sheet_price_catalog_key('18 mm Sheet',18,settings.merge('width'=>settings['length'],'length'=>settings['width']))
    refute_equal key,KeroCabinet.sheet_price_catalog_key('18 mm Sheet',12,settings)
    refute_equal key,KeroCabinet.sheet_price_catalog_key('18 mm Plywood Sheet',18,settings)
    KeroCabinet.save_sheet_price_catalog(@rows,settings.merge('prices'=>{@key=>nil}),saved)
    refute KeroCabinet.read_sheet_price_catalog.key?(key)
    assert KeroCabinet.read_sheet_price_catalog.key?(usd_key)
    assert_raises(ArgumentError) { KeroCabinet.save_sheet_price_catalog(@rows,settings,saved,{'bogus'=>'1'}) }
  end
  def test_prompt_restores_saved_catalog_and_print_has_cost_totals
    key=KeroCabinet.sheet_price_catalog_key('18 mm Sheet',18,@settings)
    Sketchup.write_default('KeroCabinet','sheet_prices_v1',JSON.generate({key=>'100.00'}))
    Sketchup.write_default('KeroCabinet','sheet_settings',JSON.generate(@settings))
    KeroCabinet.show_sheet_setup(@rows,:all)
    prompt=UI::HtmlDialog.dialogs.last
    assert_includes prompt.html,'100.00'
    prompt.callbacks['generate_layout'].call(nil,JSON.generate(@settings.merge('prices'=>{@key=>'100',@other=>'200'})))
    report=UI::HtmlDialog.dialogs.last
    assert_includes report.html,'300.00'
    assert_includes report.html,'Sheet costs (TRY)'
    Dir.mktmpdir do |directory|
      Dir.stub(:tmpdir,directory) { report.callbacks['print_report'].call(nil) }
      html=File.read(URI::DEFAULT_PARSER.unescape(UI.opened_url.sub('file://','')))
      assert_includes html,'Sheet costs (TRY)'
      assert_includes html,'300.00'
    end
  end
end
