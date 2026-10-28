# frozen_string_literal: true
require_relative 'geometry_test'
require 'minitest/autorun'

module LinkedMock
  class Definition < MockDef
    attr_reader :instances
    def initialize(name)
      super
      @instances = []
      @entities = Entities.new(self)
    end
    def valid?; true; end
    def bounds
      if points
        Struct.new(:width).new(points.map { |point| point[0] }.max)
      else
        maximum = entities.instances.map { |part| part.bounds_mm[1][0] }.max || 0
        minimum = entities.instances.map { |part| part.bounds_mm[0][0] }.min || 0
        Struct.new(:width).new((maximum-minimum)/25.4)
      end
    end
  end
  class Definitions < MockDefinitions
    def add(name)
      d = Definition.new(name)
      @all << d
      d
    end
    def remove(definition)
      @all.delete(definition)
    end
  end
  class Entities < MockEntities
    include Enumerable
    def each(&block); @instances.each(&block); end
    def add_instance(definition, transform)
      part = Instance.new(definition, transform)
      @instances << part
      definition.instances << part
      part
    end
    def clear!
      @instances.each { |part| part.definition.instances.delete(part) }
      @instances.clear
    end
  end
  class Instance < MockInstance
    def valid?; true; end
    def get_attribute(dict,key); (@attributes||{})[[dict,key]]; end
    def make_unique
      return self if definition.instances.length <= 1
      old = definition
      replacement = Sketchup.active_model.definitions.add(old.name)
      old.instance_variable_get(:@attributes)&.each { |(dict,key),value| replacement.set_attribute(dict,key,value) }
      old.entities.instances.each do |part|
        copied = replacement.entities.add_instance(part.definition,part.transformation)
        copied.name = part.name
        copied.material = part.material
      end
      old.instances.delete(self)
      @definition = replacement
      replacement.instances << self
      self
    end
  end
  class Selection < Array
    def add(part); self << part; end
  end
  class Model < MockModel
    attr_reader :active_entities, :selection
    def initialize
      super
      @definitions = Definitions.new
      @active_entities = Entities.new
      @selection = Selection.new
    end
    def start_operation(*); end
    def commit_operation; end
    def abort_operation; end
  end
end
Sketchup.const_set(:ComponentInstance, LinkedMock::Instance)

class LinkedCopyTest < Minitest::Test
  def setup
    @model = LinkedMock::Model.new
    Sketchup.active_model = @model
    @c = KeroCabinet.validate_config(KeroCabinet.clone_defaults)
    @source = KeroCabinet.build_cabinet(@c,nil)
  end

  def copy_normally(source)
    copy = @model.active_entities.add_instance(source.definition,Geom::Transformation.new([100,0,0]))
    copy.set_attribute(KeroCabinet::DICT,'config',source.get_attribute(KeroCabinet::DICT,'config'))
    copy
  end

  def test_linked_edits_share_geometry_and_settings_but_keep_positions
    copy = KeroCabinet.create_linked_copy(@source)
    assert_same @source.definition, copy.definition
    source_transform, copy_transform = @source.transformation, copy.transformation
    config = @c.merge('width'=>1800,'worktop'=>true,'base_type'=>'casters')
    config['bays'][1]['organizers']=[KeroCabinet.organizer_defaults.merge('type'=>'panels')]
    KeroCabinet.build_cabinet(KeroCabinet.validate_config(config),copy)
    assert_same @source.definition, copy.definition
    [@source,copy].each do |part|
      assert_equal 1800, JSON.parse(KeroCabinet.cabinet_config_raw(part))['width']
      assert part.definition.entities.instances.any? { |child| child.name=='Cabinet worktop' }
      assert_equal 4, part.definition.entities.instances.count { |child| child.material.name=='Caster Hardware' }
      assert_equal 3,part.definition.entities.instances.count { |child| child.name.include?(' divider ') }
      assert_equal 'panels',JSON.parse(KeroCabinet.cabinet_config_raw(part))['bays'][1]['organizers'][0]['type']
    end
    assert_same source_transform,@source.transformation
    assert_same copy_transform,copy.transformation
    assert_in_delta 1300, (copy_transform.origin[0]-source_transform.origin[0])*25.4, 0.001
  end

  def test_starting_family_does_not_link_existing_ordinary_copies
    ordinary = copy_normally(@source)
    linked = KeroCabinet.create_linked_copy(@source)
    refute_same ordinary.definition, linked.definition
    KeroCabinet.build_cabinet(KeroCabinet.validate_config(@c.merge('width'=>1600)),linked)
    assert_equal 1200, JSON.parse(KeroCabinet.cabinet_config_raw(ordinary))['width']
    assert_equal 1600, JSON.parse(KeroCabinet.cabinet_config_raw(@source))['width']
  end

  def test_make_independent_breaks_only_selected_link
    copy = KeroCabinet.create_linked_copy(@source)
    third = KeroCabinet.create_linked_copy(@source)
    KeroCabinet.make_cabinet_independent(copy)
    refute KeroCabinet.linked_cabinet?(copy)
    refute_same copy.definition,@source.definition
    KeroCabinet.build_cabinet(KeroCabinet.validate_config(@c.merge('width'=>1500)),copy)
    assert_equal 1200, JSON.parse(KeroCabinet.cabinet_config_raw(@source))['width']
    assert_same @source.definition,third.definition
    assert_equal 1500, JSON.parse(KeroCabinet.cabinet_config_raw(copy))['width']
  end

  def test_ordinary_copy_still_edits_independently
    copy = copy_normally(@source)
    KeroCabinet.build_cabinet(KeroCabinet.validate_config(@c.merge('width'=>1400)),copy)
    refute_same @source.definition,copy.definition
    assert_equal 1200, JSON.parse(KeroCabinet.cabinet_config_raw(@source))['width']
  end
end
