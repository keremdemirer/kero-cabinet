# frozen_string_literal: true
require_relative 'linked_copy_test'

class InteriorViewTest < Minitest::Test
  def setup
    @model=LinkedMock::Model.new
    Sketchup.active_model=@model
    @c=KeroCabinet.validate_config(KeroCabinet.clone_defaults)
    @c['bays'][1]['organizers']=[KeroCabinet.organizer_defaults.merge('type'=>'panels')]
    @cabinet=KeroCabinet.build_cabinet(@c,nil)
  end
  def parts(cabinet=@cabinet);cabinet.definition.entities.instances;end
  def pose(cabinet=@cabinet);parts(cabinet).to_h { |p| [p.name,p.transformation.to_a] };end
  def test_drawer_moves_as_one_assembly_and_closes_exactly_without_drift
    original=pose
    depth=parts.find { |p| p.name=='Bay 2 drawer 1 left side' }.bounds_mm.then { |low,high| high[1]-low[1] }
    3.times do
      KeroCabinet.set_interior_visibility(@cabinet,1,true)
      parts.each do |part|
        moved=part.name=='Bay 2 drawer front 1'||part.name.start_with?('Bay 2 drawer 1 ')
        matrix=part.transformation.to_a
        expected=original[part.name].dup
        expected[13]-=KeroCabinet.mm(depth*0.9) if moved
        expected.zip(matrix).each { |a,b| assert_in_delta a,b,1e-9,part.name }
        refute part.hidden
      end
      KeroCabinet.set_interior_visibility(@cabinet,1,true)
      KeroCabinet.set_interior_visibility(@cabinet,1,false)
      assert_equal original,pose
    end
  end
  def test_door_leaves_swing_outward_and_keep_hinge_edges_fixed
    originals=parts.select { |p| p.name.start_with?('Bay 1 door ') }.map { |p| KeroCabinet.interior_bounds(p) }
    closed=pose
    KeroCabinet.set_interior_visibility(@cabinet,0,true)
    doors=parts.select { |p| p.name.start_with?('Bay 1 door ') }
    doors.each_with_index do |door,index|
      low,high=originals[index]
      pivot=[index==1 ? high[0] : low[0],high[1],low[2]]
      # A point on the hinge edge remains fixed; the other edge moves toward the viewer.
      local=[index==1 ? door.definition.mesh_max[0] : 0,door.definition.mesh_max[1],0]
      door.transformation.point(local).zip(pivot).each { |a,b| assert_in_delta b,a,1e-9 }
      opened_low,_opened_high=KeroCabinet.interior_bounds(door)
      assert_operator opened_low[1],:<,low[1]-1
      refute door.hidden
    end
    KeroCabinet.set_interior_visibility(@cabinet,'all',false)
    assert_equal closed,pose
  end
  def test_regeneration_linked_copies_and_ordinary_copy_isolation
    ordinary=@model.active_entities.add_instance(@cabinet.definition,Geom::Transformation.new)
    ordinary.set_attribute(KeroCabinet::DICT,'config',JSON.generate(@c))
    original=pose(ordinary)
    KeroCabinet.set_interior_visibility(@cabinet,1,true)
    assert_equal original,pose(ordinary)
    opened=pose
    KeroCabinet.build_cabinet(@c,@cabinet)
    assert_equal opened,pose
    linked=KeroCabinet.create_linked_copy(@cabinet)
    KeroCabinet.set_interior_visibility(linked,'all',false)
    assert_same @cabinet.definition,linked.definition
    assert_equal original,pose
    # Ordinary copies of an already-open cabinet also close from their original pose.
    KeroCabinet.set_interior_visibility(@cabinet,1,true)
    copy=@model.active_entities.add_instance(@cabinet.definition,Geom::Transformation.new)
    copy.set_attribute(KeroCabinet::DICT,'config',JSON.generate(@c))
    KeroCabinet.make_cabinet_independent(copy)
    KeroCabinet.set_interior_visibility(copy,'all',false)
    assert_equal original,pose(copy)
    refute_equal original,pose
  end
  def test_mixed_section_targets_legacy_hidden_fronts_and_invalid_indices
    @c['bays']=[{'kind'=>'stack','weight'=>1,'sections'=>[
      {'kind'=>'drawer','weight'=>1,'drawers'=>1,'doors'=>1,'shelves'=>0},
      {'kind'=>'door','weight'=>2,'drawers'=>1,'doors'=>2,'shelves'=>1}]}]
    KeroCabinet.build_cabinet(KeroCabinet.validate_config(@c),@cabinet)
    original=pose
    @cabinet.definition.set_attribute(KeroCabinet::DICT,'interior_open_fronts',nil)
    @cabinet.definition.set_attribute(KeroCabinet::DICT,'interior_hidden_fronts',JSON.generate(['Bay 1 section 1 drawer front 1']))
    parts.find { |p| p.name=='Bay 1 section 1 drawer front 1' }.hidden=true
    KeroCabinet.set_interior_visibility(@cabinet,'refresh',false)
    refute parts.any?(&:hidden)
    refute_equal original,pose
    assert_raises(ArgumentError) { KeroCabinet.set_interior_visibility(@cabinet,-1,true) }
    KeroCabinet.set_interior_visibility(@cabinet,'all',false)
    assert_equal original,pose
  end
end
