# frozen_string_literal: true
require_relative 'geometry_test'
require 'minitest/autorun'

class OrganizerTest < Minitest::Test
  def settings(type='panels')
    KeroCabinet.organizer_defaults.merge('type'=>type)
  end

  def config(organizers,extra={})
    KeroCabinet.validate_config(KeroCabinet.clone_defaults.merge({
      'bays'=>[{'kind'=>'drawer','weight'=>1,'drawers'=>2,'doors'=>1,'shelves'=>0,'organizers'=>organizers}]
    }.merge(extra)))
  end

  def generate(c)
    model=MockModel.new
    Sketchup.active_model=model
    entities=MockEntities.new
    KeroCabinet.generate_parts(entities,c,model)
    [entities.instances,model]
  end

  def test_ratios_reserve_thickness_and_describe_clear_compartments
    plan=KeroCabinet.organizer_plan(settings.merge('columns'=>'1 2 1','rows'=>'1 1'),400,500,100)
    assert_equal 3,plan['pieces'].length
    a,b=plan['pieces'].select { |p| p['axis']=='y' }
    clear=(398-12)/4.0
    assert_in_delta 1+clear,a['x'],0.001
    assert_in_delta 1+3*clear+6,b['x'],0.001
    assert_equal [[246.0,6.0]],a['notches']
    assert_equal 'bottom',a['notch_from']
    assert_equal 'top',plan['pieces'].last['notch_from']
    assert_equal 90, a['height']
    assert_equal '6 mm Plywood Sheet',plan['material']
  end

  def test_directional_dividers_and_per_drawer_independence
    c=config([settings.merge('layout'=>'front_back','height'=>45),settings.merge('layout'=>'side_side')])
    parts,_model=generate(c)
    dividers=parts.select { |p| p.name.include?(' divider ') }
    assert_equal 3,dividers.length
    assert_equal 2,dividers.count { |p| p.name.start_with?('Bay 1 drawer 1') }
    assert_equal 1,dividers.count { |p| p.name.start_with?('Bay 1 drawer 2') }
    assert_equal 1,dividers.map { |p| p.material.name }.uniq.length
    dividers.each do |part|
      low,high=part.bounds_mm
      bottom=parts.find { |p| p.name==part.name.sub(/ divider \d+$/,' bottom') }
      inside_low,inside_high=bottom.bounds_mm
      assert_in_delta inside_high[2],low[2],0.001
      assert_operator low[0],:>,inside_low[0]
      assert_operator low[1],:>,inside_low[1]
      assert_operator high[0],:<,inside_high[0]
      assert_operator high[1],:<,inside_high[1]
      if part.name.start_with?('Bay 1 drawer 1')
        assert_in_delta 45,high[2]-low[2],0.001
      end
    end
  end

  def test_half_lap_profiles_have_half_height_notches_and_no_stock_scaling
    parts,_model=generate(config([settings]))
    parts.select { |p| p.name.include?(' divider ') }.each do |part|
      profile=part.definition.points.map { |p| p.map { |v| v*25.4 } }
      height=part.bounds_mm[1][2]-part.bounds_mm[0][2]
      assert profile.any? { |point| (point[2]-height/2).abs<0.001 }
      assert_equal [1,1,1],part.transformation.scale
      assert_match(/nominal stock thickness/,part.definition.description)
    end
  end

  def test_gridfinity_fit_alignment_height_and_no_overlapping_bins
    source=settings('gridfinity').merge('bins'=>[{'x'=>1,'y'=>1,'w'=>2,'d'=>3,'h'=>6}])
    plan=KeroCabinet.organizer_plan(source,500,450,100)
    assert_equal [11,10],[plan['columns'],plan['rows']]
    assert_equal [19.0,15.0],plan['origin']
    assert_in_delta 83.5,plan['bins'][0]['width'],0.001
    assert_in_delta 45.8,plan['bins'][0]['height'],0.001
    assert_equal 12,plan['max_height_units']
    assert_equal [1.0,1.0],KeroCabinet.organizer_plan(source.merge('align'=>'front_left'),500,450,100)['origin']
    assert_raises(ArgumentError) { KeroCabinet.organizer_plan(source,60,450,100) }
    assert_raises(ArgumentError) { KeroCabinet.organizer_plan(source,500,450,40) }
    source['bins'] << {'x'=>2,'y'=>2,'w'=>1,'d'=>1,'h'=>3}
    assert_raises(ArgumentError) { KeroCabinet.organizer_plan(source,500,450,100) }
  end

  def test_hardware_preview_stays_inside_box_and_is_not_sheet_stock
    source=settings('gridfinity').merge('bins'=>[{'x'=>1,'y'=>1,'w'=>2,'d'=>2,'h'=>3}])
    parts,_model=generate(config([source]))
    hardware=parts.select { |p| p.name.include?(' Gridfinity ') }
    assert_operator hardware.length,:>,6
    hardware.each do |part|
      assert_equal 'Gridfinity Preview Hardware',part.material.name
      refute_match(/sheet/i,part.definition.name)
      low,high=part.bounds_mm
      bottom=parts.find { |p| p.name=='Bay 1 drawer 1 bottom' }
      side=parts.find { |p| p.name=='Bay 1 drawer 1 left side' }
      il,ih=bottom.bounds_mm
      assert_operator low[0],:>=,il[0]
      assert_operator high[0],:<=,ih[0]
      assert_operator low[1],:>=,il[1]
      assert_operator high[1],:<=,ih[1]
      assert_operator low[2],:>=,ih[2]-0.001
      assert_operator high[2],:<,side.bounds_mm[1][2]
    end
  end

  def test_preview_is_pure_and_matches_geometry_across_hardware_and_stacked_sections
    %w[side_48 undermount_563h].product([true,false],%w[inset overlay]).each do |slide,frame,style|
      c=config([settings],{'drawer_slide'=>slide,'frame'=>frame,'style'=>style})
      c['bays']=[{'kind'=>'stack','weight'=>1,'sections'=>[
        {'kind'=>'drawer','weight'=>1,'drawers'=>1,'doors'=>1,'shelves'=>0,'organizers'=>[settings]},
        {'kind'=>'door','weight'=>1,'drawers'=>1,'doors'=>1,'shelves'=>1}]}]
      c=KeroCabinet.validate_config(c)
      plans=KeroCabinet.generate_parts(nil,c,nil,preview:true)
      assert_equal '0:0:0',plans.first['key']
      parts,_model=generate(c)
      bottom=parts.find { |p| p.name=='Bay 1 section 1 drawer 1 bottom' }
      low,high=bottom.bounds_mm
      assert_in_delta high[0]-low[0],plans.first['plan']['width'],0.001
      assert_in_delta high[1]-low[1],plans.first['plan']['depth'],0.001
    end
  end

  def test_legacy_empty_disabled_and_invalid_inputs
    parts,_model=generate(config([]))
    refute parts.any? { |p| p.name =~ /divider|Gridfinity/ }
    assert_raises(ArgumentError) { KeroCabinet.organizer_plan(settings.merge('columns'=>'0 1'),400,400,100) }
    assert_raises(ArgumentError) { KeroCabinet.organizer_plan(settings.merge('height'=>99),400,400,100) }
    assert_raises(ArgumentError) { KeroCabinet.organizer_plan(settings.merge('material'=>'hardware'),400,400,100) }
    assert_raises(ArgumentError) { KeroCabinet.organizer_plan(settings.merge('thickness'=>18,'columns'=>('1 '*12)),100,400,100) }
    assert_raises(ArgumentError) { KeroCabinet.organizer_plan(settings('gridfinity'),40,400,100) }
    assert_raises(ArgumentError) { config('bad') }
  end
end
