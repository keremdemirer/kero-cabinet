# frozen_string_literal: true
require_relative 'geometry_test'
require 'minitest/autorun'

class DrawerHeightTest < Minitest::Test
  def build(overrides = {})
    c = KeroCabinet.validate_config(KeroCabinet.clone_defaults.merge(
      'bays' => [{ 'kind' => 'drawer', 'weight' => 1, 'doors' => 1, 'drawers' => 2, 'shelves' => 0 }]).merge(overrides))
    model = MockModel.new
    Sketchup.active_model = model
    entities = MockEntities.new
    KeroCabinet.generate_parts(entities, c, model)
    [c, entities.instances.to_h { |part| [part.name, part] }]
  end

  def height(part)
    a, b = part.bounds_mm
    b[2] - a[2]
  end

  def test_fit_and_limit_for_both_hardware_families
    %w[side_35 side_48 undermount_563h].product([true, false], %w[inset overlay]).each do |hardware, frame, style|
      options = { 'drawer_slide' => hardware, 'frame' => frame, 'style' => style }
      c, fitted = build(options)
      _, capped = build(options.merge('drawer_height_mode' => 'limit', 'drawer_height_limit' => 125))
      front = fitted.fetch('Bay 1 drawer front 1')
      side = fitted.fetch('Bay 1 drawer 1 left side')
      assert_operator height(side), :>, 125
      assert_in_delta height(front) - KeroCabinet.drawer_vertical_allowance(c), height(side), 0.001
      assert_in_delta 125, height(capped.fetch('Bay 1 drawer 1 left side')), 0.001
      assert_equal front.bounds_mm, capped.fetch('Bay 1 drawer front 1').bounds_mm
      minimum, maximum = side.bounds_mm
      lower = hardware == 'undermount_563h' ? 14 : 4
      upper = hardware == 'undermount_563h' ? 6 : 4
      assert_operator minimum[2], :>=, c['toe'] + c['panel'] + lower - 0.001
      assert_operator maximum[2], :<=, c['height'] - c['panel'] - upper + 0.001
    end
  end

  def test_limit_shrinks_to_small_openings_and_rejects_hardware_violation
    options = { 'drawer_slide' => 'side_35', 'frame' => false, 'toe' => 0,
      'height' => 350, 'gap' => 1, 'drawer_height_mode' => 'limit', 'drawer_height_limit' => 125,
      'bays' => [{ 'kind' => 'drawer', 'weight' => 1, 'doors' => 1, 'drawers' => 6, 'shelves' => 0 }] }
    _, small = build(options)
    assert_operator height(small.fetch('Bay 1 drawer 1 left side')), :<, 125
    assert_operator height(small.fetch('Bay 1 drawer 1 left side')), :>=, 35.1
    error = assert_raises(ArgumentError) { build('drawer_height_mode' => 'limit', 'drawer_height_limit' => 30) }
    assert_includes error.message, 'below the selected hardware'
    assert_raises(ArgumentError) { build('drawer_height_mode' => 'unknown') }
  end
end
