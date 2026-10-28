# frozen_string_literal: true
require_relative 'linked_copy_test'

module LinkedMock
  class Instance
    attr_accessor :locked, :parent_entities
    def locked?; !!locked; end
    def definition=(value)
      @definition.instances.delete(self)
      @definition=value
      value.instances << self
    end
    def erase!
      parent_entities.instances.delete(self)
      definition.instances.delete(self)
      @erased=true
    end
    def valid?; !@erased; end
  end
  class Entities
    alias_method :original_migration_add_instance, :add_instance
    def add_instance(definition,transform)
      original_migration_add_instance(definition,transform).tap { |part| part.parent_entities=self }
    end
  end
  class Selection
    def add(items);items.is_a?(Array) ? concat(items) : self << items;end
  end
  class Model
    attr_reader :operations
    def entities; active_entities; end
    def start_operation(*args); (@operations||=[]) << [:start,args.first]; end
    def commit_operation; (@operations||=[]) << [:commit]; end
    def abort_operation; (@operations||=[]) << [:abort]; end
  end
end

class MigrationTest < Minitest::Test
  def setup
    @model=LinkedMock::Model.new
    Sketchup.active_model=@model
    @c=KeroCabinet.validate_config(KeroCabinet.clone_defaults)
  end
  def cabinet
    KeroCabinet.build_cabinet(@c,nil).tap { |part| part.set_attribute(KeroCabinet::DICT,'version','0.5.0') }
  end
  def pose(part)
    part.definition.entities.instances.to_h { |p| [p.name,p.transformation.to_a] }
  end
  def test_all_cabinets_keep_transforms_open_pose_selection_and_linked_family
    first=cabinet
    linked=KeroCabinet.create_linked_copy(first)
    ordinary=cabinet
    KeroCabinet.set_interior_visibility(first,1,true)
    original_pose=pose(first)
    first.transformation=Geom::Transformation.new([23,45,6])*Geom::Transformation.rotation([0,0,0],Z_AXIS,0.4)
    positions=[first,linked,ordinary].map { |p| p.transformation.to_a }
    @model.selection.clear
    @model.selection.add([first,ordinary])
    plan=KeroCabinet.prepare_migration(@model)
    assert_equal 3,plan[:cabinets]
    assert_equal 2,plan[:jobs].length
    before=@model.operations.length
    KeroCabinet.migrate_all(@model,plan)
    assert_equal [[:start,"Migrate all Kero Cabinets to #{KeroCabinet::VERSION}"],[:commit]],@model.operations[before..-1]
    assert_same first.definition,linked.definition
    assert_equal positions,[first,linked,ordinary].map { |p| p.transformation.to_a }
    assert_equal original_pose,pose(first)
    assert_equal [first,ordinary],@model.selection
    [first,linked,ordinary].each { |part| assert_equal KeroCabinet::VERSION,part.get_attribute(KeroCabinet::DICT,'version') }
    KeroCabinet.migrate_all(@model)
    assert_equal original_pose,pose(first)
  end
  def test_nested_shared_containers_are_scanned_once_and_unused_definitions_ignored
    container=@model.definitions.add('Container')
    nested=cabinet
    @model.entities.instances.delete(nested)
    container.entities.instances << nested
    nested.parent_entities=container.entities
    2.times { @model.entities.add_instance(container,Geom::Transformation.new) }
    unused=@model.definitions.add('Unused container')
    unused.entities.add_instance(nested.definition,Geom::Transformation.new).set_attribute(KeroCabinet::DICT,'config',JSON.generate(@c))
    plan=KeroCabinet.prepare_migration(@model)
    assert_equal 1,plan[:cabinets]
    assert_equal nested,plan[:jobs].first[:instance]
    KeroCabinet.migrate_all(@model,plan)
    assert_equal KeroCabinet::VERSION,nested.get_attribute(KeroCabinet::DICT,'version')
    @model.entities.instances.find { |part| part.definition==container }.locked=true
    error=assert_raises(ArgumentError) { KeroCabinet.prepare_migration(@model) }
    assert_match(/containing group is locked/,error.message)
  end
  def test_locked_shared_parent_and_invalid_config_stop_before_changes
    part=cabinet
    original=pose(part)
    part.locked=true
    before=@model.operations.length
    error=assert_raises(ArgumentError) { KeroCabinet.migrate_all(@model) }
    assert_match(/locked/,error.message)
    assert_equal before,@model.operations.length
    assert_equal original,pose(part)
    part.locked=false
    part.set_attribute(KeroCabinet::DICT,'config','broken json')
    assert_raises(ArgumentError) { KeroCabinet.migrate_all(@model) }
    assert_equal before,@model.operations.length
    assert_equal original,pose(part)
  end
  def test_worktop_preserves_placement_and_is_updated_in_place
    config=KeroCabinet.validate_worktop('name'=>'Top','material'=>'MDF','thickness'=>30,'x'=>0,'y'=>0,'z'=>850,'width'=>1200,'depth'=>600,
      'front_overhang'=>0,'rear_overhang'=>0,'left_overhang'=>0,'right_overhang'=>0)
    geometry=KeroCabinet.worktop_geometry(config)
    top=KeroCabinet.box(@model.entities,'Top',geometry[:stock],*geometry[:origin],*geometry[:size],{})
    top.set_attribute(KeroCabinet::DICT,'worktop_config',JSON.generate(config))
    top.transformation=Geom::Transformation.new([10,20,30])*top.transformation
    transform=top.transformation.to_a
    definition=top.definition
    @model.selection.clear
    @model.selection.add(top)
    plan=KeroCabinet.migrate_all(@model)
    assert_equal 1,plan[:worktops]
    assert_equal [top],@model.entities.instances
    assert top.valid?
    assert_equal transform,top.transformation.to_a
    assert_same definition,top.definition
    assert_equal [top],@model.selection
    assert_equal KeroCabinet::VERSION,top.get_attribute(KeroCabinet::DICT,'version')
  end
  def test_runtime_failure_uses_one_abort_without_nested_operations
    part=cabinet
    plan=KeroCabinet.prepare_migration(@model)
    part.define_singleton_method(:make_unique) { raise 'Injected failure' }
    before=@model.operations.length
    assert_raises(RuntimeError) { KeroCabinet.migrate_all(@model,plan) }
    assert_equal [[:start,"Migrate all Kero Cabinets to #{KeroCabinet::VERSION}"],[:abort]],@model.operations[before..-1]
  end
end
