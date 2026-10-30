# frozen_string_literal: true
require_relative 'geometry_test'
require 'minitest/autorun'

class SheetLayoutTest < Minitest::Test
  def row(w,h,qty=1,material='18 mm Sheet',thickness=18)
    {width:w,length:h,quantity:qty,material:material,thickness:thickness,names:['Panel']}
  end
  def settings(extra={})
    KeroCabinet.sheet_defaults.merge('width'=>1000,'length'=>1000,'edge'=>0,'kerf'=>0).merge(extra)
  end
  def assert_valid(plan,expected)
    cfg=plan[:settings]
    placed=plan[:groups].flat_map { |g| g[:sheets].flat_map { |s| s[:pieces] } }
    assert_equal expected,placed.length
    assert_equal placed.length,placed.map { |p| p[:id] }.uniq.length
    plan[:groups].each do |group|
      group[:sheets].each do |sheet|
        sheet[:pieces].each do |p|
          assert_operator p[:x],:>=,cfg['edge']-1e-6
          assert_operator p[:y],:>=,cfg['edge']-1e-6
          assert_operator p[:x]+p[:w],:<=,cfg['width']-cfg['edge']+1e-6
          assert_operator p[:y]+p[:h],:<=,cfg['length']-cfg['edge']+1e-6
        end
        sheet[:pieces].combination(2) do |a,b|
          separate=a[:x]+a[:w]+cfg['kerf']<=b[:x]+1e-6 || b[:x]+b[:w]+cfg['kerf']<=a[:x]+1e-6 ||
            a[:y]+a[:h]+cfg['kerf']<=b[:y]+1e-6 || b[:y]+b[:h]+cfg['kerf']<=a[:y]+1e-6
          assert separate,"Overlapping pieces or missing kerf: #{a}/#{b}"
        end
      end
    end
  end
  def test_exact_fit_quantity_and_kerf_change_sheet_count
    rows=[row(500,500,4)]
    plan=KeroCabinet.sheet_layout(rows,settings)
    assert_equal 1,plan[:groups][0][:sheets].length
    assert_in_delta 0,plan[:groups][0][:waste],1e-6
    assert_valid(plan,4)
    kerfed=KeroCabinet.sheet_layout(rows,settings('kerf'=>3))
    assert_operator kerfed[:groups][0][:sheets].length,:>,1
    assert_valid(kerfed,4)
  end
  def test_rotation_trim_and_oversize_are_explicit
    rows=[row(700,900,2)]
    cfg=settings('width'=>1000,'length'=>800,'edge'=>10)
    no=KeroCabinet.sheet_layout(rows,cfg.merge('rotate'=>false))
    assert_equal 2,no[:groups][0][:oversize].length
    assert_empty no[:groups][0][:sheets]
    yes=KeroCabinet.sheet_layout(rows,cfg.merge('rotate'=>true))
    assert_empty yes[:groups][0][:oversize]
    assert yes[:groups][0][:sheets][0][:pieces][0][:rotated]
    assert_valid(yes,2)
    trimmed=KeroCabinet.sheet_layout([row(1000,1000)],settings('edge'=>1))
    assert_equal 1,trimmed[:groups][0][:oversize].length
    html=KeroCabinet.sheet_layout_html(trimmed)
    assert_includes html,'INCOMPLETE'
    assert_includes html,'NOT included in the sheet count'
  end
  def test_material_thickness_separation_and_timber_exclusion
    rows=[row(400,600,1),row(400,600,1,'12 mm Sheet',12),row(400,600,1,'18 mm Plywood Sheet'),row(50,800,4,'50 x 100 mm Timber',50)]
    plan=KeroCabinet.sheet_layout(rows,settings)
    assert_equal 3,plan[:groups].length
    assert_equal 3,plan[:groups].sum { |g| g[:sheets].length }
    assert_equal 4,plan[:excluded]
    assert_valid(plan,3)
  end
  def test_deterministic_mixed_rectangles_and_randomized_nonoverlap
    random=Random.new(42)
    12.times do
      rows=Array.new(15) { row(random.rand(60..450),random.rand(451..800),random.rand(1..3)) }
      cfg=settings('edge'=>random.rand(0..25),'kerf'=>random.rand(0..5),'rotate'=>random.rand(2)==1)
      plan=KeroCabinet.sheet_layout(rows,cfg)
      assert_valid(plan,rows.sum { |r| r[:quantity] })
      assert_equal plan,KeroCabinet.sheet_layout(rows,cfg)
    end
  end
  def test_report_contains_numbered_rows_and_printable_placements
    rows=[row(300,500,2,'18 mm <Plywood> Sheet')]
    plan=KeroCabinet.sheet_layout(rows,settings)
    html=KeroCabinet.cutlist_html(rows,:all,plan)
    assert_includes html,'1. Panel'
    assert_includes html,'Sheet 1 placement'
    assert_includes html,'&lt;Plywood&gt;'
    assert_includes html,'window.sketchup.print_report()'
    assert_includes html,'page-break-inside:avoid'
    assert_includes KeroCabinet.sheet_setup_html(settings),'Generate cut list and layout'
  end
  def test_invalid_settings_and_zero_sheet_scope
    assert_raises(ArgumentError) { KeroCabinet.sheet_layout([],settings('edge'=>100,'width'=>100)) }
    assert_raises(ArgumentError) { KeroCabinet.sheet_layout([],settings('kerf'=>-1)) }
    assert_raises(ArgumentError) { KeroCabinet.sheet_layout([],settings('rotate'=>'yes')) }
    plan=KeroCabinet.sheet_layout([row(50,800,2,'Timber')],settings)
    assert_empty plan[:groups]
    assert_includes KeroCabinet.sheet_layout_html(plan),'No sheet-material parts'
  end
  def test_usage_by_thickness_totals_preserve_material_separation_and_missing_area
    rows=[row(500,500,4,'18 mm Sheet',18),row(500,500,1,'18 mm Plywood Sheet',18),
      row(500,500,2,'12 mm Sheet',12),row(1100,1200,1,'18 mm Sheet',18),row(50,800,3,'Timber',50)]
    plan=KeroCabinet.sheet_layout(rows,settings)
    summary=KeroCabinet.sheet_usage_summary(plan)
    assert_equal [12.0,18.0],summary.map { |r| r[:thickness] }
    thick=summary.last
    assert_equal 6,thick[:pieces]
    assert_equal 2,thick[:sheets]
    assert_equal 1,thick[:not_fitted]
    assert_equal 2,thick[:materials].length
    assert_in_delta 2.57,thick[:area_m2],1e-9
    assert_in_delta 37.5,thick[:waste],1e-9
    assert_equal plan[:groups].sum { |g| g[:sheets].length },summary.sum { |r| r[:sheets] }
    html=KeroCabinet.cutlist_html(rows,:all,plan)
    assert_operator html.index('Usage by thickness'),:<,html.index('Sheet 1 placement')
    assert_includes html,'2.570'
    assert_includes html,'Not fitted'
    assert_includes html,'fitted parts only'
    missing=KeroCabinet.sheet_layout([row(2000,3000)],settings)
    assert_nil KeroCabinet.sheet_usage_summary(missing).first[:waste]
  end

end
