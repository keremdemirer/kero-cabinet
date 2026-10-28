# frozen_string_literal: true
require_relative 'geometry_test'
require 'minitest/autorun'

class UndermountTest < Minitest::Test
  def build(overrides = {})
    c = KeroCabinet.validate_config(KeroCabinet.clone_defaults.merge(
      'drawer_slide' => 'undermount_563h', 'depth' => 700,
      'bays' => [{ 'kind' => 'drawer', 'weight' => 1, 'doors' => 1, 'drawers' => 3, 'shelves' => 0 }]).merge(overrides))
    model = MockModel.new
    Sketchup.active_model = model
    entities = MockEntities.new
    KeroCabinet.generate_parts(entities, c, model)
    [c, entities.instances.to_h { |p| [p.name, p] }]
  end

  def test_width_recess_clearance_and_nominal_lengths
    [true, false].product([12, 16], [229, 305, 381, 457, 533]).each do |frame, stock, length|
      c, parts = build('frame' => frame, 'drawer_thickness' => stock, 'undermount_length' => length)
      left = parts.fetch('Bay 1 drawer 1 left side').bounds_mm
      right = parts.fetch('Bay 1 drawer 1 right side').bounds_mm
      bottom = parts.fetch('Bay 1 drawer 1 bottom').bounds_mm
      opening = c['width'] - 2 * (frame ? c['frame_width'] : c['panel'])
      assert_in_delta opening - 42, right[0][0] - left[1][0], 0.001
      assert_in_delta length, left[1][1] - left[0][1], 0.001
      assert_in_delta 13, bottom[0][2] - left[0][2], 0.001
      assert_operator left[0][2], :>=, c['toe'] + c['panel'] + 14 - 0.001
      assert_in_delta bottom[0][2], parts.fetch('Bay 1 drawer 1 back rail').bounds_mm[0][2], 0.001
      parts.values.select { |part| part.name.match?(/drawer \d+ left side/) }.each do |side|
        assert_operator side.bounds_mm[1][2], :<=, c['height'] - c['panel'] - 6 + 0.001
      end
    end
  end

  def test_rejects_incompatible_stock_lengths_and_depth
    [6, 18, 30].each { |stock| assert_raises(ArgumentError) { build('drawer_thickness' => stock) } }
    assert_raises(ArgumentError) { build('undermount_length' => 400) }
    error = assert_raises(ArgumentError) { build('depth' => 350, 'undermount_length' => 533) }
    assert_includes error.message, 'shorter length'
  end

  def test_auto_uses_longest_supported_fitting_length
    [266, 328, 405, 481, 557, 800].each do |available|
      size = KeroCabinet.tandem_length(available, 0)
      assert_operator size + KeroCabinet.tandem_rear_allowance(size), :<=, available
      [229, 305, 381, 457, 533].select { |other| other > size }.each do |larger|
        assert_operator larger + KeroCabinet.tandem_rear_allowance(larger), :>, available
      end
    end
    assert_equal 457, KeroCabinet.tandem_length(800, 457)
    assert_raises(ArgumentError) { KeroCabinet.tandem_length(200, 0) }
    _, parts = build('undermount_length' => 0)
    a, b = parts.fetch('Bay 1 drawer 1 left side').bounds_mm
    assert_in_delta 533, b[1] - a[1], 0.001
  end

  def test_side_mount_uses_selected_rear_gap
    [3, 10, 25].each do |gap|
      c, parts = build('drawer_slide' => 'side_35', 'drawer_rear_gap' => gap)
      rear = KeroCabinet.case_depth(c)
      a, b = parts.fetch('Bay 1 drawer 1 left side').bounds_mm
      assert_in_delta gap, rear - b[1], 0.001
      assert_operator a[1], :>=, parts.fetch('Bay 1 drawer front 1').bounds_mm[1][1]
    end
  end

  def test_side_mount_is_preserved
    _, parts = build('drawer_slide' => 'side_35', 'drawer_thickness' => 18)
    left = parts.fetch('Bay 1 drawer 1 left side').bounds_mm
    bottom = parts.fetch('Bay 1 drawer 1 bottom').bounds_mm
    assert_in_delta left[0][2], bottom[0][2], 0.001
  end
end
