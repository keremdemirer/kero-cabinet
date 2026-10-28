# frozen_string_literal: true
require_relative 'geometry_test'
require 'minitest/autorun'

class ShallowDrawerTest < Minitest::Test
  def build(slide, overrides = {})
    c = KeroCabinet.clone_defaults.merge('drawer_slide' => slide, 'frame' => false,
      'height' => 350, 'toe' => 0, 'gap' => 1,
      'bays' => [{ 'kind' => 'drawer', 'weight' => 1, 'drawers' => 6, 'doors' => 1, 'shelves' => 0 }]).merge(overrides)
    c = KeroCabinet.validate_config(c)
    model = MockModel.new
    Sketchup.active_model = model
    entities = MockEntities.new
    KeroCabinet.generate_parts(entities, c, model)
    [c, entities.instances]
  end

  def test_six_shallow_drawers_fit_low_profile_but_not_taller_hardware
    c, parts = build('side_35')
    sides = parts.select { |p| p.name.match?(/drawer \d+ left side/) }
    assert_equal 6, sides.length
    sides.each do |part|
      min, max = part.bounds_mm
      height = max[2] - min[2]
      assert_operator height, :>=, 35.1
      assert_operator height, :<, 60
      assert_in_delta 13.0, min[0] - c['panel'], 0.001
    end
    error = assert_raises(ArgumentError) { build('side_48') }
    assert_includes error.message, '55.7'
  end

  def test_bottom_stock_and_slide_side_spaces_are_respected
    assert_equal 35.1, KeroCabinet.drawer_minimum(KeroCabinet.clone_defaults.merge('drawer_slide' => 'side_35'))
    assert_equal 47.7, KeroCabinet.drawer_minimum(KeroCabinet.clone_defaults.merge('drawer_slide' => 'side_48'))
    c, parts = build('side_48', 'height' => 500, 'drawer_bottom' => 24)
    left = parts.find { |p| p.name == 'Bay 1 drawer 1 left side' }
    assert_in_delta 13.5, left.bounds_mm[0][0] - c['panel'], 0.001
    assert_operator left.bounds_mm[1][2] - left.bounds_mm[0][2], :>=, 47.7
    assert_raises(ArgumentError) { build('undermount') }
  end

  def test_shallow_stacked_drawer_and_physical_failure_message
    section = lambda { |kind, weight| { 'kind' => kind, 'weight' => weight, 'drawers' => 1, 'doors' => 1, 'shelves' => 0 } }
    bays = [{ 'kind' => 'stack', 'weight' => 1, 'sections' => [section.call('drawer', 0.2), section.call('door', 2.2)] }]
    _, parts = build('side_35', 'height' => 850, 'toe' => 100, 'gap' => 2, 'bays' => bays)
    front = parts.find { |p| p.name == 'Bay 1 section 1 drawer front 1' }
    assert_operator front.bounds_mm[1][2] - front.bounds_mm[0][2], :<, 60
    error = assert_raises(ArgumentError) { build('side_48', 'height' => 850, 'toe' => 100, 'gap' => 2, 'bays' => bays) }
    assert_includes error.message, 'bottom section'
    assert_includes error.message, 'available front'
  end
end
