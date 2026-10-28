# frozen_string_literal: true
require_relative 'geometry_test'
require 'minitest/autorun'

class WorktopTest < Minitest::Test
  Bounds = Struct.new(:min, :max)
  Cabinet = Struct.new(:bounds, :transformation)
  def cabinet(x, width, height = 850, depth = 800)
    Cabinet.new(Bounds.new([x, 0, 0].map { |v| v/25.4 }, [x+width, depth, height].map { |v| v/25.4 }), Geom::Transformation.new)
  end
  def settings
    KeroCabinet.worktop_footprint([cabinet(0,1200), cabinet(1200,1200)]).merge(
      'name' => 'Bench top', 'material' => 'MDF', 'thickness' => 30,
      'front_overhang' => 20, 'rear_overhang' => 0, 'left_overhang' => 10, 'right_overhang' => 10)
  end

  def test_continuous_top_and_overhang_geometry
    c = KeroCabinet.validate_worktop(settings)
    g = KeroCabinet.worktop_geometry(c)
    g[:origin].zip([-10,-20,850]).each { |a,b| assert_in_delta b,a,0.001 }
    g[:size].zip([2420,820,30]).each { |a,b| assert_in_delta b,a,0.001 }
    assert_equal '30 mm MDF Worktop Sheet', g[:stock][:name]
    assert_match(/sheet/i, g[:stock][:name])
  end

  def test_mixed_heights_gaps_overlaps_and_rotations_rejected
    assert_raises(ArgumentError) { KeroCabinet.worktop_footprint([]) }
    assert_raises(ArgumentError) { KeroCabinet.worktop_footprint([cabinet(0,1200), cabinet(1200,1200,750)]) }
    assert_raises(ArgumentError) { KeroCabinet.worktop_footprint([cabinet(0,1200), cabinet(1500,1200)]) }
    assert_raises(ArgumentError) { KeroCabinet.worktop_footprint([cabinet(0,1200), cabinet(1100,1200)]) }
    assert_raises(ArgumentError) { KeroCabinet.worktop_footprint([cabinet(0,1200), cabinet(1200,1200,850,700)]) }
    rotated = cabinet(0,1200)
    rotated.transformation = Geom::Transformation.scaling(-1,1,1)
    assert_raises(ArgumentError) { KeroCabinet.worktop_footprint([rotated]) }
  end

  def test_independent_stock_is_scaled_correctly_and_reused
    model = MockModel.new
    Sketchup.active_model = model
    g = KeroCabinet.worktop_geometry(KeroCabinet.validate_worktop(settings))
    entities = MockEntities.new
    first = KeroCabinet.box(entities, 'Bench top', g[:stock], *g[:origin], *g[:size], {})
    second = KeroCabinet.box(entities, 'Second top', g[:stock], 0,0,0,1200,800,30, {})
    assert_same first.definition, second.definition
    assert_equal '30 mm MDF Worktop Sheet', first.material.name
    min,max = first.bounds_mm
    assert_in_delta 30, max[2]-min[2], 0.001
    assert_in_delta 2420, max[0]-min[0], 0.001
    assert_in_delta 820, max[1]-min[1], 0.001
    assert_in_delta 850, min[2], 0.001
  end

  def test_per_cabinet_top_follows_dimensions_and_keeps_separate_stock
    model = MockModel.new
    Sketchup.active_model = model
    %w[inset overlay].product([true,false]).each do |style, frame|
      c = KeroCabinet.validate_config(KeroCabinet.clone_defaults.merge('worktop' => true, 'style' => style, 'frame' => frame,
        'worktop_front_overhang' => 20, 'worktop_left_overhang' => 5, 'worktop_right_overhang' => 10))
      entities = MockEntities.new
      KeroCabinet.generate_parts(entities, c, model)
      top = entities.instances.find { |part| part.name == 'Cabinet worktop' }
      assert top
      low,high = top.bounds_mm
      assert_in_delta -5, low[0], 0.001
      assert_in_delta c['width']+10, high[0], 0.001
      assert_in_delta -KeroCabinet.overlay_projection(c)-20, low[1], 0.001
      assert_in_delta c['depth']+20, high[1]-low[1], 0.001
      assert_in_delta c['height'], low[2], 0.001
      assert_in_delta c['height']+30, high[2], 0.001
      assert_equal '30 mm MDF Worktop Sheet', top.material.name
      c['width'] = 1800
      c['height'] = 950
      next_entities = MockEntities.new
      KeroCabinet.generate_parts(next_entities, c, model)
      changed = next_entities.instances.find { |part| part.name == 'Cabinet worktop' }
      assert_same top.definition, changed.definition
      assert_in_delta 1815, changed.bounds_mm[1][0]-changed.bounds_mm[0][0], 0.001
      assert_in_delta 950, changed.bounds_mm[0][2], 0.001
      c['worktop'] = false
      disabled = MockEntities.new
      KeroCabinet.generate_parts(disabled, c, model)
      refute disabled.instances.any? { |part| part.name == 'Cabinet worktop' }
    end
  end

  def test_invalid_input_and_cutlist_hardware_keyword_are_rejected
    assert_raises(ArgumentError) { KeroCabinet.validate_worktop(settings.merge('thickness' => 0)) }
    assert_raises(ArgumentError) { KeroCabinet.validate_worktop(settings.merge('front_overhang' => -1)) }
    assert_raises(ArgumentError) { KeroCabinet.validate_worktop(settings.merge('material' => 'hardware')) }
  end
end
