# frozen_string_literal: true
require_relative 'linked_copy_test'

class DoubleSidedTest < Minitest::Test
  def drawer(count=2)
    {'kind'=>'drawer','weight'=>1,'drawers'=>count,'doors'=>1,'shelves'=>0,
      'organizers'=>[KeroCabinet.organizer_defaults.merge('type'=>'panels')]}
  end
  def config(extra={})
    KeroCabinet.validate_config(KeroCabinet.clone_defaults.merge('double_sided'=>true,'depth'=>1200,'bays'=>[drawer],'rear_bays'=>[drawer(3)]).merge(extra))
  end
  def generate(c)
    model=LinkedMock::Model.new
    Sketchup.active_model=model
    cabinet=KeroCabinet.build_cabinet(c,nil)
    [model,cabinet,cabinet.definition.entities.instances]
  end
  def overlap?(a,b)
    low,high=a.bounds_mm
    other_low,other_high=b.bounds_mm
    3.times.all? { |axis| [high[axis],other_high[axis]].min-[low[axis],other_low[axis]].max>0.001 }
  end
  def test_independent_boxes_shared_case_and_exact_outside_dimensions
    %w[inset overlay].product([false,true],[35,50,65],[false,true]).each do |style,frame,share,worktop|
      c=config('style'=>style,'frame'=>frame,'front_depth_share'=>share,'worktop'=>worktop)
      _model,cabinet,parts=generate(c)
      assert_equal 1,parts.count { |p| p.name=='Left side' }
      refute parts.any? { |p| p.name=='Back panel' || p.name=='Rear Left side' }
      center=parts.find { |p| p.name=='Center partition' }
      assert center
      fronts=parts.select { |p| p.name.match?(/drawer front/) }
      assert_equal 5,fronts.length
      front_boxes=parts.select { |p| p.name.match?(/^Bay 1 drawer \d+ /) }
      rear_boxes=parts.select { |p| p.name.match?(/^Rear Bay 1 drawer \d+ /) }
      front_boxes.each { |p| refute overlap?(p,center);rear_boxes.each { |q| refute overlap?(p,q),"#{p.name}/#{q.name}" } }
      rear_boxes.each { |p| refute overlap?(p,center) }
      low=parts.map { |p| p.bounds_mm[0][1] }.min
      high=parts.map { |p| p.bounds_mm[1][1] }.max
      assert_in_delta c['depth'],high-low,0.001
      assert_in_delta c['height'],parts.map { |p| p.bounds_mm[1][2] }.max,0.001
      assert_equal 5,KeroCabinet.interior_groups(cabinet).length
      preview=KeroCabinet.generate_parts(nil,c,nil,preview:true)
      assert_equal 5,preview.length
      assert_equal 3,preview.count { |row| row['key'].start_with?('rear:') }
    end
  end
  def test_rear_opens_outward_with_organizers_and_closes_without_drift
    c=config
    _model,cabinet,parts=generate(c)
    original=parts.to_h { |p| [p.name,p.transformation.to_a] }
    KeroCabinet.set_interior_visibility(cabinet,2,true)
    rear_side=parts.find { |p| p.name=='Rear Bay 1 drawer 1 left side' }
    assert_operator rear_side.transformation.origin[1],:>,original[rear_side.name][13]
    front_side=parts.find { |p| p.name=='Bay 1 drawer 1 left side' }
    assert_equal original[front_side.name],front_side.transformation.to_a
    KeroCabinet.set_interior_visibility(cabinet,'all',false)
    assert_equal original,parts.to_h { |p| [p.name,p.transformation.to_a] }
  end
  def test_rear_doors_and_mixed_bays_have_correct_targets
    rear={'kind'=>'stack','weight'=>1,'sections'=>[drawer(1),{'kind'=>'door','weight'=>2,'drawers'=>1,'doors'=>2,'shelves'=>1}]}
    _model,cabinet,parts=generate(config('rear_bays'=>[rear]))
    groups=KeroCabinet.interior_groups(cabinet)
    assert_equal 'Rear Bay 1 section 1 drawer front 1',groups[2]['fronts'].first
    rear_doors=parts.select { |p| p.name.match?(/^Rear .* door /) }
    closed=rear_doors.map(&:bounds_mm)
    KeroCabinet.set_interior_visibility(cabinet,3,true)
    rear_doors.each_with_index { |door,i| assert_operator door.bounds_mm[1][1],:>,closed[i][1][1]+1 }
  end
  def test_small_height_minimum_and_invalid_depth_split
    open_bay={'kind'=>'open','weight'=>1,'drawers'=>1,'doors'=>1,'shelves'=>0}
    c=KeroCabinet.validate_config(KeroCabinet.clone_defaults.merge('height'=>100,'base_type'=>'none','frame'=>false,'bays'=>[open_bay]))
    _model,_cabinet,parts=generate(c)
    assert_in_delta 100,parts.map { |p| p.bounds_mm[1][2] }.max,0.001
    c=KeroCabinet.validate_config(c.merge('double_sided'=>true,'depth'=>1000,'rear_bays'=>[open_bay]))
    generate(c)
    assert_raises(ArgumentError) { config('depth'=>500,'front_depth_share'=>90) }
    assert_raises(ArgumentError) { config('height'=>99) }
  end
  def test_casters_undermount_and_top_rails_use_both_faces
    %w[side_35 undermount_563h].product(%w[full rails]).each do |slide,top|
      c=config('base_type'=>'casters','drawer_slide'=>slide,'top_construction'=>top,'depth'=>1400)
      _model,_cabinet,parts=generate(c)
      assert_equal 4,parts.count { |p| p.material.name=='Caster Hardware' }
      assert parts.any? { |p| p.name=='Rear Bay 1 drawer 1 left side' }
      assert_equal 1,parts.count { |p| p.name=='Center partition' }
    end
    c=config('height'=>100,'base_type'=>'none','frame'=>false,'bays'=>[drawer(1).merge('organizers'=>[])],'rear_bays'=>[drawer(1).merge('organizers'=>[])])
    generate(c)
  end

  def test_linked_family_preserves_both_layouts_on_regeneration
    c=config
    _model,cabinet,_parts=generate(c)
    copy=KeroCabinet.create_linked_copy(cabinet)
    transform=copy.transformation.to_a
    changed=KeroCabinet.validate_config(c.merge('front_depth_share'=>60))
    KeroCabinet.build_cabinet(changed,copy)
    assert_same cabinet.definition,copy.definition
    assert_equal transform,copy.transformation.to_a
    stored=JSON.parse(KeroCabinet.cabinet_config_raw(cabinet))
    assert stored['double_sided']
    assert_equal 3,stored['rear_bays'][0]['drawers']
    assert_equal 60,stored['front_depth_share']
  end

end
