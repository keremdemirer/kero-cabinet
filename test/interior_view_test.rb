# frozen_string_literal: true
require_relative 'linked_copy_test'

class InteriorViewTest < Minitest::Test
  def setup
    @model=LinkedMock::Model.new
    Sketchup.active_model=@model
    @c=KeroCabinet.validate_config(KeroCabinet.clone_defaults)
    @cabinet=KeroCabinet.build_cabinet(@c,nil)
  end
  def hidden(cabinet=@cabinet)
    cabinet.definition.entities.instances.select(&:hidden).map(&:name)
  end
  def test_individual_drawer_and_doors_toggle_without_moving_or_removing_parts
    parts=@cabinet.definition.entities.instances
    original=parts.map { |p| [p.name,p.bounds_mm] }
    groups=KeroCabinet.interior_groups(@cabinet)
    assert_equal 5,groups.length
    KeroCabinet.set_interior_visibility(@cabinet,2,true)
    assert_equal ['Bay 2 drawer front 2'],hidden
    KeroCabinet.set_interior_visibility(@cabinet,0,true)
    assert_equal ['Bay 1 door 1','Bay 1 door 2','Bay 2 drawer front 2'],hidden
    assert_equal original,parts.map { |p| [p.name,p.bounds_mm] }
    KeroCabinet.set_interior_visibility(@cabinet,'all',false)
    assert_empty hidden
  end
  def test_view_survives_regeneration_and_linked_copies_but_isolates_ordinary_copies
    ordinary=@model.active_entities.add_instance(@cabinet.definition,Geom::Transformation.new)
    ordinary.set_attribute(KeroCabinet::DICT,'config',JSON.generate(@c))
    KeroCabinet.set_interior_visibility(@cabinet,0,true)
    assert_empty hidden(ordinary)
    KeroCabinet.build_cabinet(@c,@cabinet)
    assert_equal ['Bay 1 door 1','Bay 1 door 2'],hidden
    linked=KeroCabinet.create_linked_copy(@cabinet)
    KeroCabinet.set_interior_visibility(linked,1,true)
    assert_same @cabinet.definition,linked.definition
    assert_includes hidden,'Bay 2 drawer front 1'
    KeroCabinet.set_interior_visibility(linked,'all',false)
    assert_empty hidden
  end
  def test_mixed_sections_targets_and_invalid_indices
    @c['bays']=[{'kind'=>'stack','weight'=>1,'sections'=>[
      {'kind'=>'drawer','weight'=>1,'drawers'=>1,'doors'=>1,'shelves'=>0},
      {'kind'=>'door','weight'=>2,'drawers'=>1,'doors'=>2,'shelves'=>1}]}]
    @c=KeroCabinet.validate_config(@c)
    KeroCabinet.build_cabinet(@c,@cabinet)
    KeroCabinet.set_interior_visibility(@cabinet,1,true)
    assert_equal ['Bay 1 section 2 door 1','Bay 1 section 2 door 2'],hidden
    assert_raises(ArgumentError) { KeroCabinet.set_interior_visibility(@cabinet,-1,true) }
    KeroCabinet.set_interior_visibility(@cabinet,'all',true)
    assert_equal 3,hidden.length
  end
end
