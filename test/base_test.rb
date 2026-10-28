# frozen_string_literal: true
require_relative 'geometry_test'
require 'minitest/autorun'

class BaseTest < Minitest::Test
  def generate(settings)
    c = KeroCabinet.validate_config(KeroCabinet.clone_defaults.merge(settings))
    model = MockModel.new
    Sketchup.active_model = model
    entities = MockEntities.new
    KeroCabinet.generate_parts(entities,c,model)
    [c,entities.instances,model]
  end

  def test_no_base_starts_at_floor_and_preserves_overall_height
    [false,true].product(%w[full between]).each do |worktop,bottom|
      c,parts = generate('base_type'=>'none','worktop'=>worktop,'bottom_construction'=>bottom)
      refute parts.any? { |p| p.name =~ /toe kick|timber|caster/i }
      assert_in_delta 0, parts.find { |p| p.name=='Bottom panel' }.bounds_mm[0][2], 0.001
      assert_in_delta c['height'], parts.map { |p| p.bounds_mm[1][2] }.max, 0.001
    end
  end

  def test_casters_replace_timber_and_keep_mounting_and_total_heights
    [false,true].product([false,true],%w[full between],%w[inset overlay]).each do |worktop,frame,bottom,style|
      c,parts = generate('base_type'=>'casters','worktop'=>worktop,'frame'=>frame,'bottom_construction'=>bottom,'style'=>style)
      casters = parts.select { |p| p.material.name=='Caster Hardware' }
      assert_equal 4, casters.length
      assert_equal 2, casters.count { |p| p.name.include?('(brake)') }
      refute parts.any? { |p| p.name =~ /toe kick|timber/i }
      casters.each do |p|
        low,high = p.bounds_mm
        assert_in_delta 0, low[2], 0.001
        assert_in_delta c['caster_height'], high[2], 0.001
        assert_operator low[0], :>=, 0
        assert_operator high[0], :<=, c['width']
        assert_match(/Hardware/,p.definition.name)
      end
      assert_in_delta c['caster_height'],parts.find { |p| p.name=='Bottom panel' }.bounds_mm[0][2],0.001
      assert_in_delta c['height'],parts.map { |p| p.bounds_mm[1][2] }.max,0.001
      assert_equal 2,casters.map(&:definition).uniq.length
    end
  end

  def test_brakes_off_and_shared_hardware_reuse
    c,parts,model = generate('base_type'=>'casters','caster_front_brakes'=>false,'caster_height'=>140,'caster_diameter'=>100)
    casters=parts.select { |p| p.material.name=='Caster Hardware' }
    assert_equal 1,casters.map(&:definition).uniq.length
    refute casters.any? { |p| p.name.include?('brake') }
    entities=MockEntities.new
    KeroCabinet.generate_parts(entities,c,model)
    assert_same casters.first.definition,entities.instances.find { |p| p.material.name=='Caster Hardware' }.definition
  end

  def test_invalid_fit_rejected_and_inactive_timber_does_not_interfere
    assert_raises(ArgumentError) { generate('base_type'=>'casters','caster_height'=>50,'caster_diameter'=>75) }
    assert_raises(ArgumentError) { generate('base_type'=>'casters','width'=>300,'caster_inset'=>100) }
    %w[none casters].each { |mode| generate('base_type'=>mode,'toe'=>50,'timber_height'=>100) }
    assert_raises(ArgumentError) { generate('base_type'=>'timber','toe'=>50,'timber_height'=>100) }
  end

  def test_legacy_defaults_keep_timber_base
    c,parts=generate({})
    assert_equal 'timber',c['base_type']
    assert_in_delta c['toe'],KeroCabinet.base_height(c),0.001
    assert parts.any? { |p| p.name =~ /toe kick/i }
    refute parts.any? { |p| p.name =~ /caster/i }
  end
end
