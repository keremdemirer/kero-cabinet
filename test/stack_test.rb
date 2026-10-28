# frozen_string_literal: true
require_relative 'geometry_test'
require 'minitest/autorun'

class StackTest < Minitest::Test
  def item(kind, weight = 1)
    { 'kind' => kind, 'weight' => weight, 'doors' => 1, 'drawers' => 1, 'shelves' => 1 }
  end

  def build(sections, overrides = {})
    source = KeroCabinet.clone_defaults.merge(overrides)
    source['bays'] = [item('stack').merge('sections' => sections), item('door')]
    c = KeroCabinet.validate_config(source)
    model = MockModel.new
    Sketchup.active_model = model
    entities = MockEntities.new
    KeroCabinet.generate_parts(entities, c, model)
    [c, entities.instances]
  end

  def overlap?(first, second)
    a, b = first.bounds_mm
    c, d = second.bounds_mm
    3.times.all? { |axis| [b[axis], d[axis]].min - [a[axis], c[axis]].max > 0.001 }
  end

  def test_bottom_drawer_upper_doors_with_all_construction_modes
    [true, false].product(%w[inset overlay], %w[full rails], %w[full rails], %w[between full]).each do |frame, style, top, back, bottom|
      c, parts = build([item('drawer'), item('door', 3)],
        'frame' => frame, 'style' => style, 'top_construction' => top,
        'back_construction' => back, 'bottom_construction' => bottom)
      names = parts.map(&:name)
      assert_equal names.uniq.length, names.length
      separator = parts.find { |p| p.name == 'Bay 1 horizontal divider 1' }
      assert separator
      drawer_front = parts.find { |p| p.name == 'Bay 1 section 1 drawer front 1' }
      door = parts.find { |p| p.name == 'Bay 1 section 2 door 1' }
      assert_operator drawer_front.bounds_mm[1][2], :<, door.bounds_mm[0][2]
      sections = parts.select { |p| p.name.start_with?('Bay 1 section') }
      sections.each { |p| refute overlap?(p, separator), "#{p.name} overlaps separator" }
      parts.select { |p| p.name.include?('horizontal face frame') }.each do |rail|
        sections.each { |p| refute overlap?(p, rail), "#{p.name} overlaps face rail" }
      end
      # The second bay must retain its full-height cavity after the stacked bay.
      other = parts.find { |p| p.name == 'Bay 2 door 1' }
      assert_operator other.bounds_mm[1][2] - other.bounds_mm[0][2], :>, 600
      parts.each do |p|
        assert_operator p.bounds_mm[0][2], :>=, -0.001
        assert_operator p.bounds_mm[1][2], :<=, c['height'] + 0.001
      end
    end
  end

  def test_three_sections_reordering_and_no_duplicate_names
    _, parts = build([item('open'), item('door'), item('drawer')], 'height' => 1400)
    assert parts.any? { |p| p.name == 'Bay 1 section 1 open shelf 1' }
    assert parts.any? { |p| p.name == 'Bay 1 section 2 door 1' }
    assert parts.any? { |p| p.name == 'Bay 1 section 3 drawer front 1' }
    assert_equal 2, parts.count { |p| p.name.include?('horizontal divider') }
    dividers = parts.select { |p| p.name.include?('horizontal divider') }
    contents = parts.select { |p| p.name.start_with?('Bay 1 section') }
    dividers.each { |divider| contents.each { |part| refute overlap?(part, divider) } }
  end

  def test_invalid_sections_and_actionable_numeric_error
    assert_raises(ArgumentError) { build([item('drawer')]) }
    assert_raises(ArgumentError) { build([item('drawer'), item('stack')]) }
    assert_raises(ArgumentError) { build([item('door', 'abc'), item('drawer')]) }
    assert_raises(ArgumentError) { build([item('drawer', 0.2), item('door', 10)]) }
    error = assert_raises(ArgumentError) { build([item('drawer'), item('door')], 'toe' => 850) }
    assert_includes error.message, 'Toe kick height'
    assert_includes error.message, '850'
    assert_includes error.message, '250'
    assert_raises(ArgumentError) { build([item('drawer'), item('door')], 'timber_height' => 850) }
    assert_raises(ArgumentError) { build([item('drawer'), item('door')], 'timber_thickness' => 450) }
  end
end
