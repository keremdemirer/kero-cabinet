# frozen_string_literal: true
require_relative 'geometry_test'
require 'minitest/autorun'

class DrawerFrontTest < Minitest::Test
  def generate(options)
    c=KeroCabinet.validate_config(KeroCabinet.clone_defaults.merge(options))
    model=MockModel.new
    Sketchup.active_model=model
    entities=MockEntities.new
    KeroCabinet.generate_parts(entities,c,model)
    [c,entities.instances]
  end

  def drawer_item
    {'kind'=>'drawer','weight'=>1,'drawers'=>2,'doors'=>1,'shelves'=>0,
      'organizers'=>[KeroCabinet.organizer_defaults.merge('type'=>'panels')]}
  end

  def intersects?(a,b)
    al,ah=a.bounds_mm
    bl,bh=b.bounds_mm
    3.times.all? { |axis| [ah[axis],bh[axis]].min-[al[axis],bl[axis]].max>0.001 }
  end

  def test_boxes_contact_applied_fronts_and_clear_frame_in_all_modes
    %w[side_35 side_48 undermount_563h].product([false,true],%w[inset overlay],[9,18,32],[12,36],[false,true]).each do |slide,frame,style,front_thickness,frame_depth,stack|
      bay=stack ? {'kind'=>'stack','weight'=>1,'sections'=>[drawer_item,{'kind'=>'door','weight'=>1,'drawers'=>1,'doors'=>2,'shelves'=>1}]} : drawer_item
      c,parts=generate('drawer_slide'=>slide,'frame'=>frame,'style'=>style,'front'=>front_thickness,
        'frame_depth'=>frame_depth,'depth'=>800,'bays'=>[bay])
      prefix=stack ? 'Bay 1 section 1' : 'Bay 1'
      (1..2).each do |index|
        front=parts.find { |p| p.name=="#{prefix} drawer front #{index}" }
        box_parts=parts.select { |p| p.name.start_with?("#{prefix} drawer #{index} ") }
        rail=box_parts.find { |p| p.name.end_with?(' front rail') }
        sides=box_parts.select { |p| p.name.end_with?(' side') }
        assert_in_delta front.bounds_mm[1][1],rail.bounds_mm[0][1],0.001,[slide,frame,style,front_thickness,frame_depth,stack].inspect
        sides.each { |side| assert_in_delta front.bounds_mm[1][1],side.bounds_mm[0][1],0.001 }
        assert_operator [front.bounds_mm[1][0],rail.bounds_mm[1][0]].min-[front.bounds_mm[0][0],rail.bounds_mm[0][0]].max,:>,1
        assert_operator [front.bounds_mm[1][2],rail.bounds_mm[1][2]].min-[front.bounds_mm[0][2],rail.bounds_mm[0][2]].max,:>,1
        frame_parts=parts.select { |p| p.name.include?('face frame') }
        box_parts.each do |part|
          frame_parts.each { |frame_part| refute intersects?(part,frame_part),"#{part.name} intersects #{frame_part.name}" }
        end
        if slide=='undermount_563h'
          assert_includes [229,305,381,457,533],(sides.first.bounds_mm[1][1]-sides.first.bounds_mm[0][1]).round
          assert_operator sides.first.bounds_mm[1][1]+KeroCabinet.tandem_rear_allowance(533),:<=,KeroCabinet.case_depth(c)+0.001
        else
          assert_in_delta c['drawer_rear_gap'],KeroCabinet.case_depth(c)-sides.first.bounds_mm[1][1],0.001
          opening=c['width']-2*(frame ? c['frame_width'] : c['panel'])
          box_width=sides.last.bounds_mm[1][0]-sides.first.bounds_mm[0][0]
          assert_in_delta opening-2*KeroCabinet::DRAWER_SLIDES[slide][:side],box_width,0.001
        end
      end
      preview=KeroCabinet.generate_parts(nil,c,nil,preview:true).first['plan']
      bottom=parts.find { |p| p.name=="#{prefix} drawer 1 bottom" }
      low,high=bottom.bounds_mm
      assert_in_delta high[0]-low[0],preview['width'],0.001
      assert_in_delta high[1]-low[1],preview['depth'],0.001
    end
  end
  def test_frame_opening_cannot_widen_box_past_thick_case_sides
    %w[side_35 undermount_563h].each do |slide|
      c,parts=generate('frame'=>true,'frame_width'=>25,'panel'=>36,'frame_depth'=>36,
        'front'=>9,'drawer_slide'=>slide,'depth'=>800,'bays'=>[drawer_item])
      left=parts.find { |p| p.name=='Bay 1 drawer 1 left side' }
      right=parts.find { |p| p.name=='Bay 1 drawer 1 right side' }
      allowance=slide=='undermount_563h' ? 21-c['drawer_thickness'] : KeroCabinet::DRAWER_SLIDES[slide][:side]
      assert_in_delta c['panel']+allowance,left.bounds_mm[0][0],0.001
      assert_in_delta c['width']-c['panel']-allowance,right.bounds_mm[1][0],0.001
    end
  end

end
