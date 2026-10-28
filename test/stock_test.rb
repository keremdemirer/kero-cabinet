# frozen_string_literal: true
require_relative 'geometry_test'
require 'minitest/autorun'

class StockTest < Minitest::Test
  def setup
    @c = KeroCabinet.validate_config(KeroCabinet.clone_defaults)
    @model = MockModel.new
    Sketchup.active_model = @model
  end

  def generate
    entities = MockEntities.new
    KeroCabinet.generate_parts(entities, @c, @model)
    entities.instances
  end

  def test_stock_is_shared_across_parts_and_cabinets
    first = generate
    left = first.find { |part| part.name == 'Left side' }
    top = first.find { |part| part.name == 'Top panel' }
    assert_same left.definition, top.definition
    assert_same left.material, top.material
    assert_equal '18 mm Sheet', left.definition.name
    count = @model.definitions.all.length
    second = generate
    assert_equal count, @model.definitions.all.length
    assert_same left.definition, second.find { |part| part.name == 'Left side' }.definition
    assert_operator count, :<, first.length
  end

  def test_stock_thickness_and_types_remain_separate
    @c['drawer_bottom'] = 6
    parts = generate
    bottom = parts.find { |part| part.name == 'Bay 2 drawer 1 bottom' }
    side = parts.find { |part| part.name == 'Bay 2 drawer 1 left side' }
    assert_equal '6 mm Sheet', bottom.definition.name
    assert_equal '12 mm Sheet', side.definition.name
    assert_equal bottom.definition.name, bottom.material.name
    assert_equal side.definition.name, side.material.name
    timber = parts.find { |part| part.name == 'Toe frame front rail' }
    assert_equal '50 x 100 mm Timber', timber.definition.name
    refute_match(/sheet|plywood|mdf/i, timber.material.name)
  end

  def test_an_unowned_name_collision_is_not_reused
    unrelated = @model.definitions.add('18 mm Sheet')
    parts = generate
    refute_same unrelated, parts.find { |part| part.name == 'Left side' }.definition
    assert_nil unrelated.get_attribute(KeroCabinet::DICT, 'stock_key')
  end

  def test_cleanup_removes_only_unused_candidates
    used = Struct.new(:instances) { def valid?; true; end }.new([Object.new])
    unused = Struct.new(:instances) { def valid?; true; end }.new([])
    unrelated = Object.new
    definitions = Object.new
    removed = []
    definitions.define_singleton_method(:remove) { |item| removed << item }
    model = Struct.new(:definitions).new(definitions)
    KeroCabinet.remove_unused_part_definitions(model, [used, unused])
    assert_equal [unused], removed
    refute_includes removed, unrelated
  end
end
