# frozen_string_literal: true
# Reuse the mock SketchUp model and run the existing geometry regressions first.
require_relative 'geometry_test'
require 'minitest/autorun'

class ConstructionTest < Minitest::Test
  def build(overrides = {})
    c = KeroCabinet.validate_config(KeroCabinet.clone_defaults.merge(overrides))
    model = MockModel.new
    Sketchup.active_model = model
    entities = MockEntities.new
    KeroCabinet.generate_parts(entities, c, model)
    [c, entities.instances.to_h { |part| [part.name, part] }]
  end

  def assert_near(a, b)
    assert_in_delta a, b, 0.001
  end

  def test_all_top_back_modes_styles_and_frame_options
    %w[full rails].product(%w[full rails], %w[inset overlay], [true, false]).each do |top, back, style, frame|
      c, parts = build('construction' => 'top_bottom_full', 'top_construction' => top,
        'back_construction' => back, 'style' => style, 'frame' => frame)
      rear = c['depth'] - (back == 'full' ? c['back'] : 0)
      assert_equal top == 'full', parts.key?('Top panel')
      assert_equal back == 'full', parts.key?('Back panel')
      assert_near rear, parts.fetch('Left side').bounds_mm[1][1]
      assert_near c['depth'], parts.values.map { |p| p.bounds_mm[1][1] }.max
      if top == 'rails' || back == 'rails'
        assert_equal 'sides_full', c['construction']
        assert_near c['toe'], parts.fetch('Left side').bounds_mm[0][2]
        assert_near c['height'], parts.fetch('Left side').bounds_mm[1][2]
      end
      parts.values.select { |p| p.name.include?('support rail') }.each do |rail|
        assert_same parts.fetch('Left side').material, rail.material
        low, high = rail.bounds_mm
        assert_near c['panel'], low[0]
        assert_near c['width'] - c['panel'], high[0]
        if rail.name.start_with?('Top')
          assert_near c['rail_width'], high[1] - low[1]
          assert_near c['panel'], high[2] - low[2]
        else
          assert_near c['rail_width'], high[2] - low[2]
          assert_near c['panel'], high[1] - low[1]
        end
        parts.values.each do |other|
          next if other.equal?(rail)
          a, b = rail.bounds_mm
          x, y = other.bounds_mm
          overlap = 3.times.all? { |axis| [b[axis], y[axis]].min - [a[axis], x[axis]].max > 0.001 }
          refute overlap, "#{rail.name} overlaps #{other.name}: top=#{top}, back=#{back}"
        end
      end
      if top == 'rails' && back == 'rails'
        assert_near parts.fetch('Top rear support rail').bounds_mm[1][1], parts.fetch('Back upper support rail').bounds_mm[0][1]
      end
    end
  end

  def test_drawer_stock_preserves_outer_size_and_clearances
    _, original = build
    [6, 18, 30].product([3, 12, 24]).each do |wall, bottom|
      _, changed = build('drawer_thickness' => wall, 'drawer_bottom' => bottom)
      prefix = 'Bay 2 drawer 1'
      left = changed.fetch("#{prefix} left side").bounds_mm
      right = changed.fetch("#{prefix} right side").bounds_mm
      old_left = original.fetch("#{prefix} left side").bounds_mm
      old_right = original.fetch("#{prefix} right side").bounds_mm
      3.times { |i| assert_near old_left[0][i], left[0][i] }
      assert_near old_right[1][0], right[1][0]
      assert_near old_left[1][1], left[1][1]
      assert_near old_left[1][2], left[1][2]
      assert_near wall, left[1][0] - left[0][0]
      base = changed.fetch("#{prefix} bottom").bounds_mm
      assert_near bottom, base[1][2] - base[0][2]
      assert_near left[1][0], base[0][0]
      assert_near right[0][0], base[1][0]
      assert_near left[0][1] + wall, base[0][1]
      assert_near left[1][1] - wall, base[1][1]
      assert_equal original.fetch('Bay 2 drawer front 1').bounds_mm, changed.fetch('Bay 2 drawer front 1').bounds_mm
    end
  end

  def test_legacy_defaults_and_invalid_rail_dimensions
    legacy = KeroCabinet.clone_defaults
    %w[top_construction back_construction rail_width drawer_thickness drawer_bottom].each { |key| legacy.delete(key) }
    c = KeroCabinet.validate_config(legacy)
    assert_equal 'full', c['top_construction']
    assert_equal 'full', c['back_construction']
    assert_equal 12, c['drawer_thickness']
    assert_equal 12, c['drawer_bottom']
    assert_raises(ArgumentError) { build('top_construction' => 'rails', 'depth' => 250, 'rail_width' => 200) }
    assert_raises(ArgumentError) { build('back_construction' => 'rails', 'height' => 350, 'rail_width' => 200) }
    assert_raises(ArgumentError) { build('drawer_thickness' => 0) }
    assert_raises(ArgumentError) { build('drawer_bottom' => 100) }
  end
end
