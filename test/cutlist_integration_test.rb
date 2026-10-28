# frozen_string_literal: true
# Optional integration against a locally installed, unmodified CutList 4.1.12.
# Set CUTLIST_PLUGIN_DIR to the directory containing parts.rb and reporter.rb.
require_relative 'geometry_test'
require 'minitest/autorun'
require 'digest'

class CutListIntegrationTest < Minitest::Test
  def test_real_cutlist_scaled_dimensions_and_sheet_classification
    directory = ENV['CUTLIST_PLUGIN_DIR']
    skip 'Set CUTLIST_PLUGIN_DIR to test against installed CutList 4.1.12.' unless directory
    parts_path = File.join(directory, 'parts.rb')
    reporter_path = File.join(directory, 'reporter.rb')
    load parts_path
    cutlist = SteveR::CutList
    cutlist.define_singleton_method(:metricModel?) { true }
    cutlist.define_singleton_method(:float_round_to) { |places, number| number.round(places) }
    Numeric.class_eval do
      def inch; self; end
      def to_feet; self / 12.0; end
    end
    MockDef.class_eval do
      def bounds
        sizes=mesh_max.zip(mesh_min).map { |high,low| high-low }
        Struct.new(:width, :height, :depth).new(*sizes)
      end
    end
    MockInstance.class_eval do
      def bounds; definition.bounds; end
    end
    # Extract this named method verbatim; do not load CutList's UI/startup code.
    source = File.read(reporter_path)
    method = source[/  def isPartOrSheet\(.*?end ## end isPartOrSheet/m]
    raise 'CutList classification method not found' unless method
    classifier = Class.new
    classifier.class_eval(method, reporter_path)
    matcher = classifier.new
    model = MockModel.new
    Sketchup.active_model = model
    c = KeroCabinet.validate_config(KeroCabinet.clone_defaults)
    entities = MockEntities.new
    KeroCabinet.generate_parts(entities, c, model)
    KeroCabinet.box(entities, 'Worktop', { name: '30 mm MDF Worktop Sheet', base: [1.0,1.0,30.0], type: 'sheet' },
      0,0,850,2400,800,30,{})
    entities.instances.each do |part|
      actual = cutlist::CutListPart.new(part, part.definition.name, 'Cabinet', part.material.name, true)
      low, high = part.bounds_mm
      expected = 3.times.map { |axis| high[axis] - low[axis] }.sort
      [actual.getThickness, actual.getWidth, actual.getLength].zip(expected).each do |inches, mm|
        assert_in_delta mm, inches * 25.4, 0.001, part.name
      end
      sheet = part.definition.name.end_with?(' Sheet')
      assert_equal sheet, matcher.isPartOrSheet(%w[sheet veneer plywood hardboard mdf], part.material.name), part.name
      refute matcher.isPartOrSheet(%w[part hardware], part.definition.name)
    end
    caster_entities = MockEntities.new
    KeroCabinet.generate_parts(caster_entities,KeroCabinet.validate_config(c.merge('base_type'=>'casters')),model)
    casters = caster_entities.instances.select { |part| part.material.name=='Caster Hardware' }
    assert_equal 4,casters.length
    casters.each do |part|
      assert matcher.isPartOrSheet(%w[part hardware],part.material.name)
      refute matcher.isPartOrSheet(%w[sheet veneer plywood hardboard mdf],part.material.name)
    end
    organized = KeroCabinet.clone_defaults
    organized['bays']=[{'kind'=>'drawer','weight'=>1,'drawers'=>2,'doors'=>1,'shelves'=>0,'organizers'=>[
      KeroCabinet.organizer_defaults.merge('type'=>'panels'),
      KeroCabinet.organizer_defaults.merge('type'=>'gridfinity','bins'=>[{'x'=>1,'y'=>1,'w'=>2,'d'=>2,'h'=>3}])]}]
    organized_entities=MockEntities.new
    KeroCabinet.generate_parts(organized_entities,KeroCabinet.validate_config(organized),model)
    dividers=organized_entities.instances.select { |part| part.name.include?(' divider ') }
    assert_equal 3,dividers.length
    dividers.each do |part|
      actual=cutlist::CutListPart.new(part,part.definition.name,'Cabinet',part.material.name,true)
      low,high=part.bounds_mm
      expected=high.zip(low).map { |a,b| a-b }.sort
      [actual.getThickness,actual.getWidth,actual.getLength].zip(expected).each { |inches,mm| assert_in_delta mm,inches*25.4,0.001 }
      assert matcher.isPartOrSheet(%w[sheet veneer plywood hardboard mdf],part.material.name)
      refute matcher.isPartOrSheet(%w[part hardware],part.material.name)
    end
    previews=organized_entities.instances.select { |part| part.name.include?(' Gridfinity ') }
    assert_operator previews.length,:>,0
    previews.each do |part|
      assert matcher.isPartOrSheet(%w[part hardware],part.material.name)
      refute matcher.isPartOrSheet(%w[sheet veneer plywood hardboard mdf],part.material.name)
    end
    puts "Verified #{entities.instances.length} scaled instances with CutList source SHA256 #{Digest::SHA256.file(parts_path).hexdigest}."
  end
end
