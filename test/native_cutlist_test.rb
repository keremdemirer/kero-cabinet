# frozen_string_literal: true
require_relative 'geometry_test'
require 'minitest/autorun'
require 'csv'

class MockEntities
  def to_a; instances.dup; end
end
class MockDef
  def bounds
    sizes = mesh_max.zip(mesh_min).map { |a,b| a-b }
    Struct.new(:width,:height,:depth).new(*sizes)
  end
end
module Sketchup
  ComponentInstance = MockInstance unless const_defined?(:ComponentInstance)
end

class NativeCutlistTest < Minitest::Test
  Model = Struct.new(:entities,:selection,:edit_transform)
  def setup
    @model = MockModel.new
    Sketchup.active_model = @model
    @parts = MockEntities.new
    KeroCabinet.box(@parts, 'Left side', {name:'18 mm Sheet',base:[1,1,18],type:'sheet'},0,0,0,18,500,800,{})
    KeroCabinet.box(@parts, 'Right side', {name:'18 mm Sheet',base:[1,1,18],type:'sheet'},100,0,0,18,500,800,{})
  end
  def wrap(parts, transform=Geom::Transformation.new)
    definition=MockDef.new('Assembly')
    definition.entities.instances.concat(parts)
    MockInstance.new(definition,transform)
  end
  def report(all,selected=all,edit=Geom::Transformation.new,scope=:all)
    KeroCabinet.cutlist_rows(scope,Model.new(all,selected,edit))
  end
  def test_groups_sizes_names_and_quantity_from_actual_scaled_stock
    rows=report(@parts.instances)
    assert_equal 1,rows.length
    assert_equal [18,500,800],rows[0].values_at(:thickness,:width,:length)
    assert_equal 2,rows[0][:quantity]
    assert_equal ['Left side','Right side'],rows[0][:names]
  end
  def test_selected_only_and_ignores_unowned_and_hardware
    manual=MockInstance.new(@parts.instances.first.definition,Geom::Transformation.new)
    KeroCabinet.box(@parts,'Caster',{name:'Caster Hardware',base:[1,1,1],type:'hardware'},0,0,0,50,50,100,{})
    assert_equal 2,report(@parts.instances+[manual]).sum { |r| r[:quantity] }
    assert_equal 1,report(@parts.instances,[@parts.instances.first],Geom::Transformation.new,:selected)[0][:quantity]
    assert_empty report([manual])
    assert_raises(ArgumentError) { report([],[],Geom::Transformation.new,:selected) }
  end
  def test_nested_linked_occurrences_not_deduplicated
    parent=wrap(@parts.instances)
    copy=MockInstance.new(parent.definition,Geom::Transformation.new([10,20,30]))
    assert_equal 4,report([parent,copy])[0][:quantity]
    # Nested wrappers sharing a definition must count for each physical path.
    assert_equal 8,report([wrap([parent,copy]),wrap([parent,copy])])[0][:quantity]
  end
  def test_rotation_mirror_and_parent_scaling_and_edit_context
    rotated=Geom::Transformation.rotation([0,0,0],Z_AXIS,0.7)
    rows=report([wrap(@parts.instances,rotated*Geom::Transformation.scaling(-2,2,2))])
    assert_equal [36,1000,1600],rows[0].values_at(:thickness,:width,:length)
    selected=report(@parts.instances,[@parts.instances.first],Geom::Transformation.scaling(2,2,2),:selected)
    assert_equal [36,1000,1600],selected[0].values_at(:thickness,:width,:length)
  end
  def test_skewed_scaling_is_rejected_instead_of_inventing_stock_sizes
    transform=Geom::Transformation.scaling(2,1,1)*Geom::Transformation.rotation([0,0,0],Z_AXIS,0.7)
    assert_raises(ArgumentError) { report([wrap(@parts.instances,transform)]) }
  end
  def test_independent_worktop_and_generated_cabinet_hardware_exclusion
    worktops=MockEntities.new
    KeroCabinet.box(worktops,'Bench top',{name:'30 mm MDF Worktop Sheet',base:[1,1,30],type:'sheet'},0,0,0,2400,800,30,{})
    assert_equal [30,800,2400],report(worktops.instances)[0].values_at(:thickness,:width,:length)
    c=KeroCabinet.validate_config(KeroCabinet.clone_defaults.merge('base_type'=>'casters'))
    generated=MockEntities.new
    KeroCabinet.generate_parts(generated,c,@model)
    rows=report([wrap(generated.instances)])
    assert_equal generated.instances.length-4,rows.sum { |r| r[:quantity] }
    refute rows.any? { |r| r[:material].include?('Hardware') }
  end
  def test_html_escaping_and_csv_formulas_and_print_controls
    rows=report(@parts.instances)
    rows[0][:names]=['<img src=x>', '=HYPERLINK("x")']
    rows[0][:material]='=1+2'
    html=KeroCabinet.cutlist_html(rows,:selected)
    assert_includes html,'&lt;img src=x&gt;'
    refute_includes html,'<img src=x>'
    assert_includes html,'window.sketchup.print_report()'
    csv=CSV.parse(KeroCabinet.cutlist_csv(rows).delete_prefix("\uFEFF"))
    assert_equal "'=1+2",csv[1][5]
    rows[0][:names]=['=SUM(1,2)']
    assert_equal "'=SUM(1,2)",CSV.parse(KeroCabinet.cutlist_csv(rows).delete_prefix("\uFEFF"))[1][0]
    assert_equal '800',KeroCabinet.cutlist_number(800.0)
  end
end
