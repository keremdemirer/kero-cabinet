# frozen_string_literal: true
# Kero Cabinet v0.22.1, SketchUp 2020+; all design inputs use millimetres.
require 'sketchup.rb'
require 'json'
require_relative 'updater'

module KeroCabinet
  extend self

  %i[DICT VERSION DEFAULT DRAWER_SLIDES].each { |name| remove_const(name) if const_defined?(name, false) }
  DICT = 'kero_cabinet'.freeze
  VERSION = '0.22.1'.freeze

  DEFAULT = {
    'name' => 'Parametric Cabinet',
    'double_sided' => false,
    'front_depth_share' => 50,
    'rear_bays' => [{ 'kind'=>'drawer','weight'=>1,'doors'=>1,'drawers'=>4,'shelves'=>0 }],
    'width' => 1200,
    'height' => 850,
    'depth' => 560,
    'panel' => 18,
    'construction' => 'sides_full',
    'top_construction' => 'full',
    'bottom_construction' => 'between',
    'back_construction' => 'full',
    'rail_width' => 100,
    'drawer_thickness' => 12,
    'drawer_bottom' => 12,
    'drawer_slide' => 'side_48',
    'undermount_length' => 0,
    'drawer_rear_gap' => 10,
    'drawer_height_mode' => 'fit',
    'drawer_height_limit' => 125,
    'back' => 6,
    'front' => 18,
    'base_type' => 'timber',
    'caster_height' => 100,
    'caster_diameter' => 75,
    'caster_inset' => 30,
    'caster_front_brakes' => true,
    'toe' => 100,
    'toe_frame' => true,
    'worktop' => false,
    'worktop_thickness' => 30,
    'worktop_material' => 'MDF',
    'worktop_front_overhang' => 0,
    'worktop_rear_overhang' => 0,
    'worktop_left_overhang' => 0,
    'worktop_right_overhang' => 0,
    'timber_height' => 100,
    'timber_thickness' => 50,
    'frame' => true,
    'frame_width' => 38,
    'frame_depth' => 20,
    'style' => 'inset',
    'gap' => 2,
    'bays' => [
      { 'kind' => 'door', 'weight' => 1, 'doors' => 2, 'shelves' => 1, 'drawers' => 4 },
      { 'kind' => 'drawer', 'weight' => 1, 'doors' => 1, 'shelves' => 0, 'drawers' => 4 }
    ]
  }.freeze

  def clone_defaults
    JSON.parse(JSON.generate(DEFAULT))
  end

  def mm(number)
    number.to_f / 25.4
  end

  def editors_open?
    @dialogs && !@dialogs.empty?
  end

  def close_editors_for_reload
    (@dialogs || []).dup.each(&:close)
    @dialogs = []
  end

  def show_dialog(instance = nil)
    config = clone_defaults
    if instance && instance.valid?
      raw = cabinet_config_raw(instance)
      if raw.is_a?(String)
        stored = JSON.parse(raw)
        config = clone_defaults.merge(stored)
        unless stored.key?('bottom_construction')
          config['bottom_construction'] = stored['construction'] == 'top_bottom_full' ? 'full' : 'between'
        end
      end
    end

    config['_linked_count'] = instance && linked_cabinet?(instance) ? instance.definition.instances.length : 0
    dialog = UI::HtmlDialog.new(
      dialog_title: instance ? 'Kero Cabinet | Edit' : 'Kero Cabinet | New',
      preferences_key: 'KeroCabinet.ParametricCabinet',
      scrollable: true,
      resizable: true,
      width: 620,
      height: 790,
      min_width: 500,
      min_height: 540,
      style: UI::HtmlDialog::STYLE_DIALOG
    )

    initial = JSON.generate(config).gsub('</', '<\\/')
    dialog.set_html(dialog_html.sub('/* INITIAL_CONFIG */ null', initial))
    dialog.add_action_callback('submit') do |_context, raw|
      begin
        parsed = JSON.parse(raw)
        validated = validate_config(parsed)
        build_cabinet(validated, instance)
        dialog.close
      rescue StandardError => e
        dialog.execute_script("showError(#{JSON.generate(e.message)})")
        puts "[Kero Cabinet] #{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}" 
      end
    end

    dialog.add_action_callback('interior_view') do |_context|
      if instance && instance.valid?
        show_interior_view(instance)
      else
        UI.messagebox('Create the cabinet first, then open Interior view.')
      end
    end
    dialog.add_action_callback('organizer_preview') do |_context, raw|
      begin
        request=JSON.parse(raw)
        rows=generate_parts(nil,validate_config(request.fetch('config')),nil,preview:true)
        version=Integer(request.fetch('version'))
        dialog.execute_script("receiveOrganizerPreview(#{JSON.generate(rows)},#{version})")
      rescue StandardError => e
        dialog.execute_script("showError(#{JSON.generate(e.message)})")
      end
    end
    @dialogs ||= []
    @dialogs << dialog
    dialog.set_on_closed { @dialogs.delete(dialog) }
    dialog.show
    dialog.center
  rescue StandardError => e
    UI.messagebox("Could not open Kero Cabinet:\n#{e.message}")
  end

  def field_label(key)
    { 'toe' => 'Toe kick height', 'timber_height' => 'Upright timber height',
      'timber_thickness' => 'Timber thickness', 'panel' => 'Case panel thickness',
      'drawer_thickness' => 'Drawer box thickness', 'drawer_bottom' => 'Drawer bottom thickness',
      'weight' => 'Height weight' }.fetch(key) { key.tr('_', ' ').capitalize }
  end

  def number_between!(config, key, low, high)
    n = Float(config[key])
    raise ArgumentError, "#{field_label(key)}: enter #{low}-#{high} mm (current value: #{config[key]})." unless n.finite? && n.between?(low, high)
    config[key] = n
  rescue TypeError, ArgumentError => e
    raise ArgumentError, e.message.include?(field_label(key)) ? e.message : "#{field_label(key)}: enter a valid number."
  end

  def integer_between!(hash, key, low, high)
    n = Integer(hash[key])
    raise ArgumentError, "#{field_label(key)}: enter a value between #{low} and #{high}." unless n.between?(low, high)
    hash[key] = n
  rescue TypeError, ArgumentError => e
    raise ArgumentError, e.message.include?(field_label(key)) ? e.message : "#{field_label(key)}: enter a valid integer."
  end

  # Manufacturer minimum drawer height, not just the metal slide height.
  # Clearances above/below the box are Kero Cabinet allowances, not quoted specs.
  DRAWER_SLIDES = {
    'side_35' => { name: 'Low-profile side mount (2132C reference)', minimum: 35.1, side: 13.0 },
    'side_48' => { name: 'Easy-close side mount (3832EC reference)', minimum: 47.7, side: 13.5 },
    'undermount_563h' => { name: 'Undermount (TANDEM 563H reference)', minimum: 0, recess: 13, lower: 14, upper: 6 }
  }.freeze

  def drawer_minimum(c)
    profile = DRAWER_SLIDES.fetch(c['drawer_slide'])
    [profile[:minimum], profile.fetch(:recess, 0) + c['drawer_bottom'] + 10.0].max
  end

  def drawer_vertical_allowance(c)
    c['drawer_slide'] == 'undermount_563h' ? 20 : 8
  end

  def tandem_rear_allowance(length)
    length == 229 ? 37 : 24
  end

  def tandem_length(available, selected)
    return selected unless selected == 0
    length = [533, 457, 381, 305, 229].find { |size| size + tandem_rear_allowance(size) <= available + 0.001 }
    raise ArgumentError, 'No supported TANDEM length fits this depth. Increase cabinet depth or use Side mount.' unless length
    length
  end

  def base_height(c)
    case c['base_type']
    when 'none' then 0.0
    when 'casters' then c['caster_height']
    else c['toe']
    end
  end

  def caster_dimensions(c)
    diameter = c['caster_diameter']
    { plate_length: [76.0,diameter].max, plate_width: 60.0,
      wheel_width: [[diameter*0.3,18.0].max,40.0].min }
  end

  def caster_positions(c)
    dims = caster_dimensions(c)
    side = c['bottom_construction'] == 'full' ? 0 : c['panel']
    front = c['frame'] ? c['frame_depth'] : 0
    rear = case_depth(c)
    left_x = side + c['caster_inset'] + dims[:plate_length]/2
    right_x = c['width'] - side - c['caster_inset'] - dims[:plate_length]/2
    front_y = front + c['caster_inset'] + dims[:plate_width]/2
    rear_y = rear - c['caster_inset'] - dims[:plate_width]/2
    if right_x-left_x < dims[:plate_length]+1 || rear_y-front_y < dims[:plate_width]+1
      raise ArgumentError, 'Caster plates do not fit the bottom panel. Reduce edge inset/wheel diameter or increase cabinet width/depth.'
    end
    [[left_x,front_y,true],[right_x,front_y,true],[left_x,rear_y,false],[right_x,rear_y,false]]
  end

  def case_height(c)
    c['height'] - (c['worktop'] ? c['worktop_thickness'] : 0)
  end

  def overlay_projection(c)
    return 0 unless c['style'] == 'overlay' && c['bays'].is_a?(Array)
    fronts = c['bays'].any? do |bay|
      next false unless bay.is_a?(Hash)
      %w[door drawer].include?(bay['kind']) ||
        (bay['kind'] == 'stack' && bay['sections'].is_a?(Array) &&
          bay['sections'].any? { |section| section.is_a?(Hash) && %w[door drawer].include?(section['kind']) })
    end
    fronts ? c['front'] : 0
  end

  def case_depth(c)
    return c['depth']-overlay_projection(c)-rear_projection(c) if c['double_sided']
    c['depth'] - (c['back_construction'] == 'full' ? c['back'] : 0) - overlay_projection(c)
  end

  def validate_config(source)
    raise ArgumentError, 'Invalid configuration data.' unless source.is_a?(Hash)
    c = clone_defaults.merge(source)
    c['double_sided']=c['double_sided']==true
    begin
      c['front_depth_share']=Float(c['front_depth_share'])
      raise ArgumentError unless c['front_depth_share'].finite? && c['front_depth_share'].between?(10,90)
    rescue TypeError,ArgumentError
      raise ArgumentError, 'Front depth share must be between 10% and 90%.'
    end
    c['name'] = c['name'].to_s.strip[0, 80]
    c['name'] = 'Parametric Cabinet' if c['name'].empty?
    {
      'width' => [300, 5000], 'height' => [100, 3500], 'depth' => [250, 5000],
      'rail_width' => [40, 200], 'drawer_thickness' => [6, 30],
      'worktop_thickness' => [6,100], 'worktop_front_overhang' => [0,300],
      'worktop_rear_overhang' => [0,300], 'worktop_left_overhang' => [0,300], 'worktop_right_overhang' => [0,300],
      'drawer_height_limit' => [25, 3000], 'drawer_rear_gap' => [3, 50], 'drawer_bottom' => [3, 24], 'panel' => [9, 36], 'back' => [3, 24], 'front' => [9, 32],
      'caster_height' => [35,400], 'caster_diameter' => [20,250], 'caster_inset' => [0,150],
      'toe' => [0, 250], 'timber_height' => [20, 200],
      'timber_thickness' => [10, 100], 'frame_width' => [25, 90],
      'frame_depth' => [12, 36], 'gap' => [1, 6]
    }.each { |key, (low, high)| number_between!(c, key, low, high) }
    unless %w[fit limit].include?(c['drawer_height_mode'])
      raise ArgumentError, 'Drawer box height must use Fit available height or Limit height.'
    end
    unless DRAWER_SLIDES.key?(c['drawer_slide'])
      raise ArgumentError, 'Select a supported drawer slide profile.'
    end
    if c['drawer_slide'] == 'undermount_563h'
      if c['drawer_thickness'] < 12 || c['drawer_thickness'] > 16
        raise ArgumentError, 'The TANDEM 563H reference supports 12-16 mm drawer sides. Change Drawer box thickness or select Side mount.'
      end
      integer_between!(c, 'undermount_length', 0, 533)
      unless [0, 229, 305, 381, 457, 533].include?(c['undermount_length'])
        raise ArgumentError, 'Choose Auto or an available TANDEM drawer length: 229, 305, 381, 457, or 533 mm.'
      end
    end
    c['construction'] = c['construction'].to_s
    unless %w[sides_full top_bottom_full].include?(c['construction'])
      raise ArgumentError, 'Construction must use full-height sides or full-width top and bottom panels.'
    end
    %w[top_construction back_construction].each do |key|
      raise ArgumentError, "#{key}: choose full or rails." unless %w[full rails].include?(c[key])
    end
    if c['top_construction'] == 'rails' || (!c['double_sided'] && c['back_construction'] == 'rails')
      c['construction'] = 'sides_full'
    end
    unless source.key?('bottom_construction')
      c['bottom_construction'] = source['construction'] == 'top_bottom_full' ? 'full' : 'between'
    end
    unless %w[between full].include?(c['bottom_construction'])
      raise ArgumentError, 'Bottom construction must be between or full.'
    end
    c['worktop'] = c['worktop'] == true
    if c['worktop']
      normalized = validate_worktop(cabinet_worktop_config(c))
      c['worktop_material'] = normalized['material']
    end
    unless %w[none timber casters].include?(c['base_type'])
      raise ArgumentError, 'Choose No base, Timber toe kick, or Casters.'
    end
    c['caster_front_brakes'] = c['caster_front_brakes'] == true
    if c['base_type'] == 'casters'
      if c['caster_height'] < c['caster_diameter'] + 12
        raise ArgumentError, 'Caster mounting height must exceed wheel diameter by at least 12 mm for the representative bracket.'
      end
    end
    c['toe_frame'] = (c['toe_frame'] == true)
    if c['base_type'] == 'timber' && c['toe_frame'] && c['toe'] > 0 && c['toe'] < c['timber_height']
      raise ArgumentError, 'Toe kick height must be at least the upright timber height, or disable the support frame.'
    end
    c['frame'] = (c['frame'] == true)
    c['style'] = c['style'].to_s
    raise ArgumentError, 'Door style must be inset or overlay.' unless %w[inset overlay].include?(c['style'])
    if base_height(c) + 2 * [c['panel'], (c['frame'] ? c['frame_width'] : 0)].max >= case_height(c)
      raise ArgumentError, 'Height is insufficient for the selected base and top/bottom sections.'
    end
    frame_depth = c['frame'] ? c['frame_depth'] : 0.0
    if case_depth(c) - frame_depth < 190
      raise ArgumentError, 'Case depth is too small.'
    end
    case_rear = case_depth(c)
    rear_limit = case_rear - (c['back_construction'] == 'rails' ? c['panel'] : 0)
    if c['top_construction'] == 'rails' && rear_limit - frame_depth <= 2 * c['rail_width']
      raise ArgumentError, 'Top support rails need more depth or a smaller rail width.'
    end
    if !c['double_sided'] && c['back_construction'] == 'rails' && case_height(c) - base_height(c) - 2 * c['panel'] <= 2 * c['rail_width']
      raise ArgumentError, 'Back support rails need more height or a smaller rail width.'
    end
    unless c['bays'].is_a?(Array) && c['bays'].length.between?(1, 6)
      raise ArgumentError, 'Between 1 and 6 vertical bays are required.'
    end
    c['bays'].each do |bay|
      raise ArgumentError, 'Invalid bay data.' unless bay.is_a?(Hash)
      validate_bay_item(bay, true)
      if bay['kind'] == 'stack'
        unless bay['sections'].is_a?(Array) && bay['sections'].length.between?(2, 6)
          raise ArgumentError, 'Stacked bays require 2-6 sections, ordered bottom to top.'
        end
        bay['sections'].each { |section| validate_bay_item(section, false) }
      end
    end
    caster_positions(c) if c['base_type'] == 'casters'
    total = c['bays'].sum { |b| b['weight'] }
    widths = c['bays'].map { |b| c['width'] * b['weight'] / total }
    minimum = c['panel'] * 2 + (c['frame'] ? c['frame_width'] : 0) + 110
    raise ArgumentError, "Each bay must be at least #{minimum.round} mm wide. Increase the width or adjust the weights." if widths.any? { |w| w < minimum }
    if c['double_sided']
      unless c['rear_bays'].is_a?(Array) && c['rear_bays'].length.between?(1,6)
        raise ArgumentError, 'Rear layout needs 1-6 bays.'
      end
      configs,body,zone=double_face_configs(c)
      configs.each_with_index do |face,index|
        begin
          validated=validate_config(face)
          c['rear_bays']=validated['bays'] if index==1
        rescue ArgumentError => e
          raise ArgumentError, "#{index==1 ? 'Rear' : 'Front'} layout: #{e.message} Increase total depth or adjust Front depth share."
        end
      end
    end
    c
  end

  def validate_bay_item(item, allow_stack)
    raise ArgumentError, 'Invalid section data.' unless item.is_a?(Hash)
    kinds = allow_stack ? %w[door drawer open stack] : %w[door drawer open]
    raise ArgumentError, 'Invalid bay or section type.' unless kinds.include?(item['kind'])
    begin
      item['weight'] = Float(item['weight'])
    rescue TypeError, ArgumentError
      raise ArgumentError, 'Bay/section weight must be a number between 0.2 and 10.'
    end
    unless item['weight'].finite? && item['weight'].between?(0.2, 10)
      raise ArgumentError, 'Bay/section weight must be between 0.2 and 10.'
    end
    return if item['kind'] == 'stack'
    integer_between!(item, 'doors', 1, 2)
    integer_between!(item, 'drawers', 1, 8)
    integer_between!(item, 'shelves', 0, 8)
    if item['kind']=='drawer' && item.key?('organizers')
      raise ArgumentError, 'Drawer organizers must be a list with up to 8 entries.' unless item['organizers'].is_a?(Array) && item['organizers'].length<=8
      item['organizers']=item['organizers'].map do |organizer|
        begin
          validate_organizer(organizer)
        rescue ArgumentError => e
          raise ArgumentError, "Drawer organizer: #{e.message}"
        end
      end
    end
  end

  def organizer_defaults
    { 'type'=>'none', 'layout'=>'grid', 'thickness'=>6.0, 'material'=>'Plywood',
      'columns'=>'1 1 1', 'rows'=>'1 1', 'height'=>0.0, 'clearance'=>1.0,
      'align'=>'center', 'bins'=>[] }
  end

  def organizer_ratios(value)
    values = value.to_s.split(/[\s,;]+/).map { |part| Float(part) }
    unless values.length.between?(1,12) && values.all? { |v| v.finite? && v.between?(0.1,100) }
      raise ArgumentError, 'Organizer ratios need 1-12 positive numbers between 0.1 and 100, such as 1 2 1.'
    end
    values
  rescue TypeError, ArgumentError
    raise ArgumentError, 'Organizer ratios need 1-12 positive numbers between 0.1 and 100, such as 1 2 1.'
  end

  def validate_organizer(source)
    raise ArgumentError, 'Invalid drawer organizer settings.' unless source.is_a?(Hash)
    o = organizer_defaults.merge(source)
    raise ArgumentError, 'Choose None, Panel dividers or Gridfinity for the organizer.' unless %w[none panels gridfinity].include?(o['type'])
    return o if o['type']=='none'
    number_between!(o,'clearance',0,5)
    if o['type']=='panels'
      raise ArgumentError, 'Choose Front-to-back, Side-to-side or Grid for panel dividers.' unless %w[front_back side_side grid].include?(o['layout'])
      number_between!(o,'thickness',3,18)
      number_between!(o,'height',0,500)
      o['material']=o['material'].to_s.strip
      unless o['material'].match?(/\A[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}\z/) && o['material'] !~ /part|hardware/i
        raise ArgumentError, 'Organizer material needs an English name without part or hardware keywords.'
      end
      organizer_ratios(o['columns'])
      organizer_ratios(o['rows'])
    else
      raise ArgumentError, 'Gridfinity alignment must be Center or Front left.' unless %w[center front_left].include?(o['align'])
      raise ArgumentError, 'Gridfinity supports up to 64 bins per drawer.' unless o['bins'].is_a?(Array) && o['bins'].length<=64
      o['bins'].each do |bin|
        raise ArgumentError, 'Invalid Gridfinity bin.' unless bin.is_a?(Hash)
        %w[x y w d h].each do |key|
          value=Float(bin[key]) rescue nil
          raise ArgumentError, 'Gridfinity bin cells and height units must be whole numbers.' unless value && value.finite? && value==value.floor
        end
        %w[x y].each { |key| integer_between!(bin,key,1,120) }
        %w[w d].each { |key| integer_between!(bin,key,1,120) }
        integer_between!(bin,'h',1,60)
      end
    end
    o
  end

  # Equal values give equal clear compartments; thickness is reserved first.
  def organizer_divisions(length, ratios, thickness)
    clear = length-(ratios.length-1)*thickness
    raise ArgumentError, 'Organizer panel thickness leaves insufficient compartment space.' if clear/ratios.sum*ratios.min < 10
    cursor = 0.0
    ratios[0...-1].map do |ratio|
      cursor += clear*ratio/ratios.sum
      position = cursor
      cursor += thickness
      position
    end
  end

  # Pure layout calculation shared by model generation and the editor fit preview.
  def organizer_plan(source, width, depth, height)
    o=validate_organizer(source)
    plan={ 'type'=>o['type'], 'width'=>width, 'depth'=>depth, 'height'=>height, 'pieces'=>[], 'bins'=>[] }
    return plan if o['type']=='none'
    margin=o['clearance']
    w,d=width-2*margin,depth-2*margin
    raise ArgumentError, 'Organizer clearance leaves no usable space.' if [w,d].min<10
    if o['type']=='panels'
      t=o['thickness']
      ph=o['height'].zero? ? height-10 : o['height']
      raise ArgumentError, "Organizer height must be at least #{[12,t].max.round(1)} mm and no more than #{(height-2).round(1)} mm in this drawer." unless ph>=[12,t].max && ph<=height-2
      xs=o['layout']=='side_side' ? [] : organizer_divisions(w,organizer_ratios(o['columns']),t)
      ys=o['layout']=='front_back' ? [] : organizer_divisions(d,organizer_ratios(o['rows']),t)
      xs.each { |x| plan['pieces'] << { 'axis'=>'y', 'x'=>x+margin, 'y'=>margin, 'length'=>d, 'thickness'=>t, 'height'=>ph, 'notches'=>ys.map { |y| [y, t] }, 'notch_from'=>'bottom' } }
      ys.each { |y| plan['pieces'] << { 'axis'=>'x', 'x'=>margin, 'y'=>y+margin, 'length'=>w, 'thickness'=>t, 'height'=>ph, 'notches'=>xs.map { |x| [x, t] }, 'notch_from'=>'top' } }
      plan['material']="#{stock_number(t)} mm #{o['material']} Sheet"
    else
      cols,rows=(w/42).floor,(d/42).floor
      raise ArgumentError, 'Gridfinity needs at least one 42 x 42 mm cell inside the drawer.' if cols<1 || rows<1
      ox=margin+(o['align']=='center' ? (w-cols*42)/2 : 0)
      oy=margin+(o['align']=='center' ? (d-rows*42)/2 : 0)
      plan.merge!('columns'=>cols,'rows'=>rows,'origin'=>[ox,oy], 'grid_width'=>cols*42,'grid_depth'=>rows*42,
        'edge_gaps'=>[ox,width-ox-cols*42,oy,depth-oy-rows*42], 'base_height'=>5,
        'max_height_units'=>[( (height-2-5-3.8)/7 ).floor,0].max)
      raise ArgumentError, 'Gridfinity baseplate preview needs at least 7.3 mm of internal height.' if height<7.3
      o['bins'].each_with_index do |bin,index|
        if bin['x']+bin['w']-1>cols || bin['y']+bin['d']-1>rows
          raise ArgumentError, "Gridfinity bin #{index+1} is outside the #{cols} x #{rows} grid."
        end
        bh=bin['h']*7+3.8
        raise ArgumentError, "Gridfinity bin #{index+1} is too tall. Maximum #{plan['max_height_units']} height units with the preview base and top clearance." if bh+5>height-2
        o['bins'][0...index].each do |other|
          if bin['x']<other['x']+other['w'] && other['x']<bin['x']+bin['w'] && bin['y']<other['y']+other['d'] && other['y']<bin['y']+bin['d']
            raise ArgumentError, "Gridfinity bins #{o['bins'].index(other)+1} and #{index+1} overlap."
          end
        end
        plan['bins'] << bin.merge('px'=>ox+(bin['x']-1)*42+0.25,'py'=>oy+(bin['y']-1)*42+0.25,
          'width'=>bin['w']*42-0.5,'depth'=>bin['d']*42-0.5,'height'=>bh)
      end
    end
    plan
  end

  # Profile includes real half-lap notches; bounding dimensions remain CutList stock sizes.
  def organizer_panel(entities,tag,piece,material,origin,model)
    length,t,height=piece.values_at('length','thickness','height')
    notch_top=piece['notch_from']=='top'
    edge=[[0,0]]
    if !notch_top
      piece['notches'].each { |start,width| edge.concat([[start,0],[start,height/2],[start+width,height/2],[start+width,0]]) }
    end
    edge.concat([[length,0],[length,height]])
    if notch_top
      piece['notches'].reverse_each { |start,width| edge.concat([[start+width,height],[start+width,height/2],[start,height/2],[start,height]]) }
    end
    edge << [0,height]
    key="organizer-panel-v1:#{material}:#{piece['axis']}:#{length}:#{t}:#{height}:#{piece['notch_from']}:#{piece['notches']}"
    definition=model.definitions.find { |item| item.get_attribute(DICT,'stock_key')==key }
    unless definition
      definition=model.definitions.add("#{material} - divider")
      definition.set_attribute(DICT,'stock_key',key)
      definition.description='Removable drawer divider. Grid crossings use half-height slots at nominal stock thickness; fit to actual sheet thickness.'
      points=edge.map { |a,b| piece['axis']=='x' ? [mm(a),0,mm(b)] : [0,mm(a),mm(b)] }
      face=definition.entities.add_face(points)
      raise 'Could not create organizer divider profile.' unless face
      face.reverse! unless face.normal.samedirection?(piece['axis']=='x' ? Y_AXIS : X_AXIS)
      face.pushpull(mm(t))
    end
    stock_material=model.materials[material]||model.materials.add(material)
    stock_material.color=Sketchup::Color.new(214,179,130)
    instance=entities.add_instance(definition,Geom::Transformation.new([origin[0]+piece['x'],origin[1]+piece['y'],origin[2]].map { |v| mm(v) }))
    instance.name=tag
    instance.material=stock_material
    instance.set_attribute(DICT,'part_name',tag)
  end

  def generate_organizer(entities,tag,plan,origin,model)
    plan['pieces'].each_with_index { |piece,index| organizer_panel(entities,"#{tag} divider #{index+1}",piece,plan['material'],origin,model) }
    return unless plan['type']=='gridfinity'
    cache={}
    # Preview envelopes intentionally omit mating feet, sockets, magnets and print tolerances.
    stock={name:'Gridfinity Preview Hardware',base:[1.0,1.0,1.0],type:'hardware'}
    add=lambda do |name,x,y,z,w,d,h|
      box(entities,"#{tag} Gridfinity #{name}",stock,origin[0]+x,origin[1]+y,origin[2]+z,w,d,h,cache)
    end
    ox,oy=plan['origin']
    add.call('baseplate envelope',ox,oy,0,plan['grid_width'],plan['grid_depth'],5)
    (1...plan['columns']).each { |index| add.call("grid column #{index}",ox+index*42-0.25,oy,5,0.5,plan['grid_depth'],0.3) }
    (1...plan['rows']).each { |index| add.call("grid row #{index}",ox,oy+index*42-0.25,5,plan['grid_width'],0.5,0.3) }

    plan['bins'].each_with_index do |bin,index|
      x,y,w,d,h=bin.values_at('px','py','width','depth','height')
      label="bin #{index+1}"
      add.call("#{label} bottom",x,y,5,w,d,1.2)
      add.call("#{label} left wall",x,y,6.2,1.2,d,h-1.2)
      add.call("#{label} right wall",x+w-1.2,y,6.2,1.2,d,h-1.2)
      add.call("#{label} front wall",x+1.2,y,6.2,w-2.4,1.2,h-1.2)
      add.call("#{label} back wall",x+1.2,y+d-1.2,6.2,w-2.4,1.2,h-1.2)
    end
    model.materials[stock[:name]].color=Sketchup::Color.new(142,174,156)
  end

  def stock_number(value)
    value.to_f.round(4).to_s.sub(/\.0+\z/, '')
  end

  def part_stock(name, role, c)
    if role == 'Toe kick timber' || role == 'Face frame'
      sizes = role == 'Toe kick timber' ? c.values_at('timber_thickness', 'timber_height') : c.values_at('frame_depth', 'frame_width')
      a, b = sizes.sort
      { name: "#{stock_number(a)} x #{stock_number(b)} mm Timber", base: [1.0, a, b], type: 'timber' }
    else
      thickness = case role
      when 'Back panel' then c['back']
      when 'Door / drawer front' then c['front']
      when 'Drawer box' then name.end_with?(' bottom') ? c['drawer_bottom'] : c['drawer_thickness']
      else c['panel']
      end
      { name: "#{stock_number(thickness)} mm Sheet", base: [1.0, 1.0, thickness], type: 'sheet' }
    end
  end

  # One owned definition per stock; dimensions belong to each scaled instance.
  # CutList 4.1.12 multiplies definition bounds by instance axis scales.
  def box(entities, name, stock, x, y, z, sx, sy, sz, cache)
    dims = [sx, sy, sz]
    return if dims.any? { |v| v <= 0.25 }
    model = Sketchup.active_model
    key = "stock-v1:#{stock[:name]}"
    entry = cache[key]
    unless entry
      definition = model.definitions.find { |item| item.get_attribute(DICT, 'stock_key') == key }
      unless definition
        definition = model.definitions.add(stock[:name])
        dx, dy, dz = stock[:base].map { |v| mm(v) }
        face = definition.entities.add_face([[0,0,0], [dx,0,0], [dx,dy,0], [0,dy,0]])
        raise "Could not create stock component: #{stock[:name]}" unless face
        face.reverse! unless face.normal.samedirection?(Z_AXIS)
        face.pushpull(dz)
        definition.description = "Kero Cabinet shared #{stock[:type]} stock. Dimensions are set on instances."
        definition.set_attribute(DICT, 'stock_key', key)
      end
      material = model.materials[stock[:name]]
      unless material
        material = model.materials.add(stock[:name])
        material.color = Sketchup::Color.new(*(stock[:type] == 'sheet' ? [214,179,130] : [196,159,106]))
      end
      entry = cache[key] = [definition, material]
    end
    definition, material = entry
    scale = dims.zip(stock[:base]).map { |actual, base| actual.to_f / base }
    transform = Geom::Transformation.new([x,y,z].map { |v| mm(v) }) * Geom::Transformation.scaling(*scale)
    instance = entities.add_instance(definition, transform)
    instance.name = name
    instance.material = material
    instance.set_attribute(DICT, 'part_name', name)
    instance
  end

  def obsolete_part_definitions(entities)
    entities.grep(Sketchup::ComponentInstance).map do |part|
      definition = part.definition
      owned = definition.get_attribute(DICT, 'stock_key') ||
        (definition.name.start_with?('KC | ') && definition.description == part.name)
      definition if owned
    end.compact.uniq
  end

  def remove_unused_part_definitions(model, candidates)
    candidates.each do |definition|
      next unless definition.valid? && definition.instances.empty?
      model.definitions.remove(definition)
    end
  end

  def rear_projection(c)
    overlay_projection(c.merge('bays'=>c['rear_bays'],'double_sided'=>false))
  end

  def double_face_configs(c)
    body=c['depth']-overlay_projection(c)-rear_projection(c)
    usable=body-c['panel']
    front_zone=usable*c['front_depth_share']/100.0
    rear_zone=usable-front_zone
    configs=[['front',c['bays'],front_zone,overlay_projection(c)],['rear',c['rear_bays'],rear_zone,rear_projection(c)]].map do |face,bays,zone,projection|
      c.merge('double_sided'=>false,'bays'=>JSON.parse(JSON.generate(bays)),
        'depth'=>zone+projection+c['panel']/2.0,'back'=>c['panel']/2.0,'back_construction'=>'full')
    end
    [configs,body,front_zone]
  end

  def generate_double_parts(entities,c,model,preview:false)
    configs,body,front_zone=double_face_configs(c)
    previews=[]
    configs.each_with_index do |face,index|
      if preview
        rows=generate_single_parts(nil,face,nil,preview:true,layout_only:true)
      else
        created=[]
        proxy=Object.new
        flip=Geom::Transformation.new([mm(c['width']),mm(body),0])*Geom::Transformation.rotation([0,0,0],Z_AXIS,Math::PI)
        proxy.define_singleton_method(:add_instance) do |definition,transform|
          part=entities.add_instance(definition,index==1 ? flip*transform : transform)
          created << part
          part
        end
        rows=generate_single_parts(proxy,face,model,layout_only:true)
        if index==1
          created.each do |part|
            part.name="Rear #{part.name}"
            part.set_attribute(DICT,'part_name',part.name)
          end
        end
      end
      rows.each { |row| row['key']="rear:#{row['key']}" if index==1 }
      previews.concat(rows)
    end
    w,t,h,toe=c['width'],c['panel'],case_height(c),base_height(c)
    fd=c['frame'] ? c['frame_depth'] : 0.0
    palette={}
    add=lambda { |name,role,x,y,z,sx,sy,sz| box(entities,name,part_stock(name,role,c),x,y,z,sx,sy,sz,palette) unless preview }
    full_bottom=c['bottom_construction']=='full'
    full_top=c['construction']=='top_bottom_full' && c['top_construction']=='full'
    side_bottom=toe+(full_bottom ? t : 0)
    side_top=h-(full_top ? t : 0)
    add.call('Left side','Case',0,fd,side_bottom,t,body-2*fd,side_top-side_bottom)
    add.call('Right side','Case',w-t,fd,side_bottom,t,body-2*fd,side_top-side_bottom)
    add.call('Bottom panel','Case',full_bottom ? 0 : t,fd,toe,full_bottom ? w : w-2*t,body-2*fd,t)
    if c['top_construction']=='full'
      add.call('Top panel','Case',full_top ? 0 : t,fd,h-t,full_top ? w : w-2*t,body-2*fd,t)
    else
      add.call('Top front support rail','Case',t,fd,h-t,w-2*t,c['rail_width'],t)
      add.call('Top rear support rail','Case',t,body-fd-c['rail_width'],h-t,w-2*t,c['rail_width'],t)
    end
    add.call('Center partition','Case',t,front_zone,toe+t,w-2*t,t,h-toe-2*t)
    if c['base_type']=='timber' && toe>0
      recess=[65.0,(body-2*fd)/3.0].min
      add.call('Toe kick front','Case',0,fd+recess,0,w,t,toe)
      add.call('Rear toe kick front','Case',0,body-fd-recess-t,0,w,t,toe)
      if c['toe_frame']
        base_c=c.merge('double_sided'=>false,'depth'=>body-fd-recess-t+c['back']+overlay_projection(c))
        # Merge nearby support locations from both face layouts to avoid overlapping rails.
        boundaries=[0.0,w]
        [c['bays'],c['rear_bays']].each_with_index do |bays,index|
          cursor=0.0
          total=bays.sum { |b| b['weight'] }
          bays[0...-1].each { |bay| cursor+=w*bay['weight']/total;boundaries << (index==1 ? w-cursor : cursor) }
        end
        merged=[0.0]
        spacing=c['toe']>c['timber_height'] ? [c['timber_thickness'],c['timber_height']].max : c['timber_thickness']
        boundaries.uniq.sort[1...-1].each do |x|
          if merged.length>1 && x-merged.last<spacing
            merged[-1]=(merged.last+x)/2
          else
            merged << x
          end
        end
        merged << w
        generate_toe_frame(add,base_c,merged,fd)
      end
    end
    if c['base_type']=='casters'
      caster_c=c.merge('double_sided'=>false,'depth'=>body-fd+c['back']+overlay_projection(c))
      preview ? caster_positions(caster_c) : generate_casters(entities,caster_c,model)
    end
    if c['worktop'] && !preview
      geometry=worktop_geometry(cabinet_worktop_config(c))
      box(entities,'Cabinet worktop',geometry[:stock],*geometry[:origin],*geometry[:size],palette)
    end
    previews
  end

  def generate_parts(entities,c,model,preview:false)
    return generate_double_parts(entities,c,model,preview:preview) if c['double_sided']
    generate_single_parts(entities,c,model,preview:preview)
  end

  def generate_single_parts(entities, c, model, preview: false, layout_only: false)
    organizer_previews=[]
    w, h, d = c.values_at('width', 'height', 'depth')
    h = case_height(c)
    d = case_depth(c)
    t, bt, ft, toe = c.values_at('panel', 'back', 'front', 'toe')
    toe = base_height(c)
    face_frame = c['frame']
    fw = face_frame ? c['frame_width'] : 0.0
    fd = face_frame ? c['frame_depth'] : 0.0
    g = c['gap']
    palette = {}
    add = lambda do |name, material, x, y, z, sx, sy, sz|
      outer=%w[Left\ side Right\ side Bottom\ panel Top\ panel Back\ panel Top\ front\ support\ rail Top\ rear\ support\ rail Back\ upper\ support\ rail Back\ lower\ support\ rail Toe\ kick\ front]
      next if layout_only && outer.include?(name)
      box(entities, name, part_stock(name, material, c), x, y, z, sx, sy, sz, palette) unless preview
    end

    # Carcass construction. The selected full-length direction also determines
    # the physical size of the panels, not merely a visual highlight.
    # The back thickness is reserved within the requested overall depth.
    # The back is applied OUTSIDE the carcass, not captured between its parts.
    # This also keeps top and bottom flush with the rear edge of the side panels.
    rear_inside = d - (c['back_construction'] == 'rails' ? t : 0)
    depth_inside = rear_inside - fd
    full_bottom = c['bottom_construction'] == 'full'
    full_top = c['construction'] == 'top_bottom_full' && c['top_construction'] == 'full'
    side_bottom = toe + (full_bottom ? t : 0)
    side_top = h - (full_top ? t : 0)
    add.call('Left side', 'Case', 0, fd, side_bottom, t, d - fd, side_top - side_bottom)
    add.call('Right side', 'Case', w - t, fd, side_bottom, t, d - fd, side_top - side_bottom)
    add.call('Bottom panel', 'Case', full_bottom ? 0 : t, fd, toe,
      full_bottom ? w : w - 2*t, d - fd, t)
    if c['top_construction'] == 'full'
      add.call('Top panel', 'Case', full_top ? 0 : t, fd, h - t,
        full_top ? w : w - 2*t, d - fd, t)
    end
    rail = c['rail_width']
    if c['top_construction'] == 'rails'
      add.call('Top front support rail', 'Case', t, fd, h - t, w - 2*t, rail, t)
      add.call('Top rear support rail', 'Case', t, rear_inside - rail, h - t, w - 2*t, rail, t)
    end
    if c['back_construction'] == 'full'
      add.call('Back panel', 'Back panel', 0, d, toe, w, bt, h - toe)
    else
      upper = c['top_construction'] == 'full' ? h - t : h
      add.call('Back upper support rail', 'Case', t, d - t, upper - rail, w - 2*t, t, rail)
      add.call('Back lower support rail', 'Case', t, d - t, toe + t, w - 2*t, t, rail)
    end
    if c['base_type'] == 'timber' && toe > 0
      recess = [65.0, (d-fd)/3.0].min
      add.call('Toe kick front', 'Case', 0, fd + recess, 0, w, t, toe)
    end

    bay_total = c['bays'].sum { |b| b['weight'] }
    bounds = [0.0]
    c['bays'].each { |bay| bounds << bounds.last + w * bay['weight'] / bay_total }
    bounds[-1] = w
    n = c['bays'].length

    generate_toe_frame(add, c, bounds, fd) if c['base_type'] == 'timber' && c['toe_frame'] && toe > 0 && !layout_only
    generate_casters(entities, c, model) if c['base_type'] == 'casters' && !preview && !layout_only

    # Full-height intermediate panels and face-frame stiles align with bays.
    (1...n).each do |i|
      x = bounds[i]
      add.call("Divider #{i}", 'Case', x - t/2, fd, toe + t, t, depth_inside, h - toe - 2*t)
    end

    if face_frame
      add.call('Left face frame stile', 'Face frame', 0, 0, toe, fw, fd, h - toe)
      add.call('Right face frame stile', 'Face frame', w-fw, 0, toe, fw, fd, h-toe)
      add.call('Bottom face frame rail', 'Face frame', fw, 0, toe, w-2*fw, fd, fw)
      add.call('Top face frame rail', 'Face frame', fw, 0, h-fw, w-2*fw, fd, fw)
      (1...n).each do |i|
        add.call("Middle face frame stile #{i}", 'Face frame', bounds[i]-fw/2, 0,
                 toe+fw, fw, fd, h-toe-2*fw)
      end
    end

    door_bottom = toe + (face_frame ? fw : t)
    door_top = h - (face_frame ? fw : t)
    cavity_bottom = toe + t
    cavity_top = h - t

    c['bays'].each_with_index do |bay, i|
      cavity_bottom = toe + t
      cavity_top = h - t
      start_x = bounds[i]
      end_x = bounds[i+1]
      opening_left = i.zero? ? (face_frame ? fw : t) : start_x + (face_frame ? fw/2 : t/2)
      opening_right = i == n-1 ? (w - (face_frame ? fw : t)) : end_x - (face_frame ? fw/2 : t/2)
      cavity_left = i.zero? ? t : start_x + t/2
      cavity_right = i == n-1 ? w-t : end_x-t/2
      cavity_width = cavity_right - cavity_left

      # Inset fronts fit within openings. Overlay fronts cover part of the frame.
      if c['style'] == 'inset'
        front_left = opening_left + g
        front_right = opening_right - g
        front_bottom = door_bottom + g
        front_top = door_top - g
        front_y = face_frame ? g : fd
      else
        front_left = start_x + (i.zero? ? g : g/2)
        front_right = end_x - (i == n-1 ? g : g/2)
        front_bottom = toe + g
        front_top = h - g
        front_y = -ft
      end
      front_width = front_right - front_left
      front_height = front_top - front_bottom
      raise ArgumentError, "Bay #{i+1}: available opening is too small." if front_width < 60 || front_height < (bay['kind'] == 'drawer' ? drawer_minimum(c) + drawer_vertical_allowance(c) : 1)

      sections = bay['kind'] == 'stack' ? bay['sections'] : [bay]
      total_weight = sections.sum { |section| section['weight'] }
      section_bounds = [cavity_bottom]
      sections.each do |section|
        section_bounds << section_bounds.last + (h - t - toe - t) * section['weight'] / total_weight
      end
      section_bounds[-1] = h - t
      if c['style'] == 'overlay' && sections.length > 1
        # Use the same gap-centered front grid as a uniform drawer bank.
        # A bottom weight of 1/4 then matches drawer 1 of a four-drawer bay.
        cumulative = 0.0
        sections[0...-1].each_with_index do |section, index|
          cumulative += section['weight']
          section_bounds[index+1] = front_bottom + (front_height + g) * cumulative / total_weight - g/2
        end
      end
      outer_front_bottom, outer_front_top = front_bottom, front_top
      sections.each_with_index do |section, section_index|
        section_name = sections.length == 1 ? "Bay #{i+1}" : "Bay #{i+1} section #{section_index+1}"
        lower = section_bounds[section_index]
        upper = section_bounds[section_index+1]
        cavity_bottom = lower + (section_index.zero? ? 0 : t/2)
        cavity_top = upper - (section_index == sections.length-1 ? 0 : t/2)
        front_margin = c['style'] == 'inset' ? (face_frame ? fw/2 : t/2) + g : g/2
        front_bottom = section_index.zero? ? outer_front_bottom : lower + front_margin
        front_top = section_index == sections.length-1 ? outer_front_top : upper - front_margin
        front_height = front_top - front_bottom
        minimum_section = section['kind'] == 'drawer' ? drawer_minimum(c) + drawer_vertical_allowance(c) : [section['kind']=='door' ? 20 : 1,section['shelves']*t+section['shelves']+1].max
        if front_height < minimum_section || cavity_top - cavity_bottom < minimum_section
          label = sections.length == 1 ? section_name : "Bay #{i+1}, #{section_index == sections.length-1 ? 'top' : section_index.zero? ? 'bottom' : 'middle'} section"
          raise ArgumentError, "#{label}: available front #{front_height.round(1)} mm, internal opening #{(cavity_top-cavity_bottom).round(1)} mm. Need at least #{minimum_section.round(1)} mm for the selected contents/slide. Increase this section's height ratio or select a lower-profile slide."
        end
        if section_index > 0
          add.call("Bay #{i+1} horizontal divider #{section_index}", 'Case',
            cavity_left, fd, lower - t/2, cavity_width, depth_inside, t)
          if face_frame
            add.call("Bay #{i+1} horizontal face frame rail #{section_index}", 'Face frame',
              opening_left, 0, lower - fw/2, opening_right - opening_left, fd, fw)
          end
        end
      case section['kind']
      when 'door'
        # Inset doors occupy case depth. Keep shelves behind the door back,
        # with the configured gap, while preserving their rear alignment.
        shelf_y = c['style'] == 'inset' ? [fd, front_y + ft + g].max : fd
        shelf_depth = rear_inside - shelf_y
        count = section['doors']
        item_width = (front_width - (count - 1)*g) / count
        count.times do |j|
          x = front_left + j*(item_width + g)
          add.call("#{section_name} door #{j+1}", 'Door / drawer front',
                   x, front_y, front_bottom, item_width, ft, front_height)
        end
        section['shelves'].times do |j|
          z = cavity_bottom + (j+1)*(cavity_top - cavity_bottom)/(section['shelves']+1.0) - t/2
          add.call("#{section_name} internal shelf #{j+1}", 'Case',
                   cavity_left, shelf_y, z, cavity_width, shelf_depth, t)
        end
      when 'drawer'
        count = section['drawers']
        cell = (front_height - (count-1)*g)/count
        required_box = drawer_minimum(c)
        if cell < required_box + drawer_vertical_allowance(c)
          raise ArgumentError, "#{section_name}: each drawer front has #{cell.round(1)} mm; this slide and stock need at least #{(required_box+drawer_vertical_allowance(c)).round(1)} mm. Reduce drawer count or increase the section height."
        end
        count.times do |j|
          z_front = front_bottom + j*(cell+g)
          add.call("#{section_name} drawer front #{j+1}", 'Door / drawer front',
                   front_left, front_y, z_front, front_width, ft, cell)
          # Preserve outer box dimensions and runner clearances as stock changes.
          profile = DRAWER_SLIDES.fetch(c['drawer_slide'])
          undermount = c['drawer_slide'] == 'undermount_563h'
          dt = c['drawer_thickness']
          bottom_t = c['drawer_bottom']
          side_clearance = undermount ? 21.0 - dt : profile[:side]
          runner_left = face_frame ? [opening_left,cavity_left].max : cavity_left
          runner_width = face_frame ? [opening_right,cavity_right].min - runner_left : cavity_width
          dbx = runner_left + side_clearance
          dbw = runner_width - 2*side_clearance
          # The applied front fastens directly to the box front. Runner clearance
          # belongs at the sides/rear, not between these mating surfaces.
          dby = front_y + ft
          available_depth = rear_inside - dby
          dbd = undermount ? tandem_length(available_depth, c['undermount_length']) : available_depth - c['drawer_rear_gap']
          rear_allowance = undermount ? tandem_rear_allowance(dbd) : c['drawer_rear_gap']
          if undermount && rear_inside - dby < dbd + rear_allowance
            raise ArgumentError, "#{section_name}: the #{dbd} mm TANDEM drawer needs at least #{dbd+rear_allowance} mm behind the box front. Select a shorter length or increase depth."
          end
          lower_clearance = undermount ? 14.0 : 4.0
          upper_clearance = undermount ? 6.0 : 4.0
          allowance = lower_clearance + upper_clearance
          recess = undermount ? 13.0 : 0.0
          # Clip each box to its own front interval before applying clearance.
          # Overlay fronts extend beyond the case, so moving an already-sized
          # box inward can otherwise push it into the next drawer.
          # Boxes must pass through the clear frame opening when pulled forward,
          # including the bottom/top and mixed-section horizontal frame rails.
          box_cavity_bottom = face_frame ? [cavity_bottom, section_index.zero? ? door_bottom : lower+fw/2].max : cavity_bottom
          box_cavity_top = face_frame ? [cavity_top, section_index==sections.length-1 ? door_top : upper-fw/2].min : cavity_top
          box_lower = [z_front, box_cavity_bottom].max + lower_clearance
          box_upper = [z_front + cell, box_cavity_top].min - upper_clearance
          dbh = box_upper - box_lower
          if c['drawer_height_mode'] == 'limit'
            if c['drawer_height_limit'] < required_box
              raise ArgumentError, "Drawer height limit #{c['drawer_height_limit']} mm is below the selected hardware/stock minimum of #{required_box.round(1)} mm. Increase the limit or choose Fit available height."
            end
            dbh = [dbh, c['drawer_height_limit']].min
          end
          dbz = undermount ? box_lower : box_lower + (box_upper - box_lower - dbh) / 2
          raise ArgumentError, 'Insufficient internal space for the drawer box.' if dbw < 80 || dbd < 100 || dbh + 0.001 < required_box
          if dbw - 2*dt <= 0.25 || dbd - 2*dt <= 0.25 || dbh - recess - bottom_t <= 0.25
            raise ArgumentError, 'Drawer stock is too thick for the available box dimensions.'
          end
          tag = "#{section_name} drawer #{j+1}"
          add.call("#{tag} left side", 'Drawer box', dbx, dby, dbz, dt, dbd, dbh)
          add.call("#{tag} right side", 'Drawer box', dbx+dbw-dt, dby, dbz, dt, dbd, dbh)
          add.call("#{tag} front rail", 'Drawer box', dbx+dt, dby, dbz+recess, dbw-2*dt, dt, dbh-recess)
          add.call("#{tag} back rail", 'Drawer box', dbx+dt, dby+dbd-dt, dbz+recess, dbw-2*dt, dt, dbh-recess)
          add.call("#{tag} bottom", 'Drawer box', dbx+dt, dby+dt, dbz+recess,
                   dbw-2*dt, dbd-2*dt, bottom_t)
          begin
            plan=organizer_plan((section['organizers'] || [])[j] || organizer_defaults,dbw-2*dt,dbd-2*dt,dbh-recess-bottom_t)
            organizer_previews << { 'key'=>"#{i}:#{bay['kind']=='stack' ? section_index : -1}:#{j}", 'plan'=>plan }
            generate_organizer(entities,tag,plan,[dbx+dt,dby+dt,dbz+recess+bottom_t],model) unless preview
          rescue ArgumentError => e
            raise ArgumentError, "#{tag} organizer: #{e.message}"
          end
        end
      when 'open'
        section['shelves'].times do |j|
          z = cavity_bottom + (j+1)*(cavity_top - cavity_bottom)/(section['shelves']+1.0) - t/2
          add.call("#{section_name} open shelf #{j+1}", 'Case',
                   cavity_left, fd, z, cavity_width, depth_inside, t)
        end
      end
      end
    end
    if c['worktop'] && !preview && !layout_only
      geometry = worktop_geometry(cabinet_worktop_config(c))
      box(entities, 'Cabinet worktop', geometry[:stock], *geometry[:origin], *geometry[:size], palette)
    end
    organizer_previews
  end

  # Full-width front/rear rails; transverse members butt between them.
  # At the default 100 mm toe height the upright 100 mm timbers sit on the floor.
  def generate_toe_frame(add, c, bounds, front_offset)
    w, d, toe = c.values_at('width', 'depth', 'toe')
    d = case_depth(c)
    height, thickness = c.values_at('timber_height', 'timber_thickness')
    recess = [65.0, (d - front_offset) / 3.0].min
    front_y = front_offset + recess + c['panel']
    rear_y = d - thickness
    inside_depth = rear_y - front_y - thickness
    if inside_depth <= 0.25 || w <= 2 * thickness + 0.25
      raise ArgumentError, 'The toe kick support frame does not fit. Reduce timber thickness or increase case dimensions.'
    end
    z = toe - height
    add.call('Toe frame front rail', 'Toe kick timber', 0, front_y, z, w, thickness, height)
    add.call('Toe frame rear rail', 'Toe kick timber', 0, rear_y, z, w, thickness, height)
    add.call('Toe frame left rail', 'Toe kick timber', 0, front_y + thickness, z, thickness, inside_depth, height)
    add.call('Toe frame right rail', 'Toe kick timber', w - thickness, front_y + thickness, z, thickness, inside_depth, height)

    # Support each bay boundary, adding intermediate supports for spans over 600 mm.
    centers = bounds[1...-1].dup
    bounds.each_cons(2) do |left, right|
      divisions = ((right - left) / 600.0).ceil
      (1...divisions).each { |i| centers << left + (right - left) * i / divisions }
    end
    centers.sort.each_with_index do |x, i|
      if x - thickness / 2 < thickness || x + thickness / 2 > w - thickness
        raise ArgumentError, 'A toe frame cross rail is too close to an end rail. Reduce timber thickness.'
      end
      add.call("Toe frame cross rail #{i + 1}", 'Toe kick timber',
        x - thickness / 2, front_y + thickness, z, thickness, inside_depth, height)
    end

    # Taller toe spaces need legs below the top frame to reach the floor.
    return unless z > 0.25
    leg_width = height
    supports = [leg_width / 2.0] + centers.sort + [w - leg_width / 2.0]
    if supports.each_cons(2).any? { |left, right| right - left < leg_width }
      raise ArgumentError, 'Toe frame legs would overlap. Reduce upright timber height or increase bay widths.'
    end
    supports.each_with_index do |x, i|
      [front_y, rear_y].each_with_index do |y, j|
        add.call("Toe frame leg #{i + 1} #{j == 0 ? 'front' : 'rear'}", 'Toe kick timber',
          x - leg_width / 2, y, 0, leg_width, thickness, z)
      end
    end
  end

  def hardware_box(entities, x, y, z, width, depth, height)
    points = [[x,y,z],[x+width,y,z],[x+width,y+depth,z],[x,y+depth,z]].map { |point| point.map { |v| mm(v) } }
    face = entities.add_face(points)
    raise 'Could not create caster geometry.' unless face
    face.reverse! unless face.normal.samedirection?(Z_AXIS)
    face.pushpull(mm(height))
  end

  # A representative caster, not a manufacturer mounting/drilling model.
  def generate_casters(entities, c, model)
    dims = caster_dimensions(c)
    height, diameter, width = c['caster_height'], c['caster_diameter'], dims[:wheel_width]
    material = model.materials['Caster Hardware'] || model.materials.add('Caster Hardware')
    material.color = Sketchup::Color.new(90,96,100)
    caster_positions(c).each_with_index do |(x,y,front),index|
      brake = front && c['caster_front_brakes']
      key = "caster-v1:#{height}:#{diameter}:#{brake}"
      definition = model.definitions.find { |item| item.get_attribute(DICT,'stock_key') == key }
      unless definition
        definition = model.definitions.add("Caster Hardware - #{stock_number(height)} mm#{brake ? ' brake' : ''}")
        definition.set_attribute(DICT,'stock_key',key)
        definition.description = 'Representative caster hardware. Verify actual mounting height, footprint, fixings and load rating with the supplier.'
        raw = definition.entities
        hardware_box(raw,-dims[:plate_length]/2,-dims[:plate_width]/2,height-4,dims[:plate_length],dims[:plate_width],4)
        fork_width = [diameter*0.25,25].min
        [-width/2-5,width/2+2].each do |fork_y|
          hardware_box(raw,-fork_width/2,fork_y,diameter/2,fork_width,3,height-4-diameter/2)
        end
        edges = raw.add_circle([0,mm(-width/2),mm(diameter/2)],Y_AXIS,mm(diameter/2),24)
        face = raw.add_face(edges)
        raise 'Could not create caster wheel.' unless face
        face.reverse! unless face.normal.samedirection?(Y_AXIS)
        face.pushpull(mm(width))
        hardware_box(raw,diameter*0.2,-width/2,diameter+2,diameter*0.25,width,3) if brake
      end
      part = entities.add_instance(definition,Geom::Transformation.new([mm(x),mm(y),0]))
      part.name = "#{front ? 'Front' : 'Rear'} #{index.even? ? 'left' : 'right'} caster#{brake ? ' (brake)' : ''}"
      part.material = material
      part.set_attribute(DICT,'part_name',part.name)
    end
  end

  def build_cabinet(c, instance, manage_operation: true, update_selection: true)
    model = Sketchup.active_model
    model.start_operation(instance ? 'Edit Kero Cabinet' : 'Create Kero Cabinet', true) if manage_operation
    begin
      obsolete = []
      if instance && instance.valid?
        raise 'The selected object is no longer available.' unless instance.is_a?(Sketchup::ComponentInstance)
        instance.make_unique unless linked_cabinet?(instance)
        definition = instance.definition
        obsolete = obsolete_part_definitions(definition.entities)
        definition.entities.clear!
      else
        definition = model.definitions.add(c['name'])
        instance = model.active_entities.add_instance(definition, Geom::Transformation.new)
      end
      generate_parts(definition.entities, c, model)
      definition.name = c['name']
      definition.description = "Kero Cabinet #{VERSION}, created from parameters in millimetres"
      definition.set_attribute(DICT, 'config', JSON.generate(c))
      targets = linked_cabinet?(instance) ? definition.instances : [instance]
      targets.each do |target|
        target.name = c['name']
        target.set_attribute(DICT, 'config', JSON.generate(c))
        target.set_attribute(DICT, 'version', VERSION)
      end
      apply_interior_visibility(instance)
      if update_selection
        model.selection.clear
        model.selection.add(instance)
      end
      remove_unused_part_definitions(model, obsolete)
      model.commit_operation if manage_operation
    rescue StandardError
      model.abort_operation if manage_operation
      raise
    end
    instance
  end

  # Independent worktops span adjacent, equally deep, translation-only cabinets.
  def worktop_footprint(cabinets)
    raise ArgumentError, 'Select one or more Kero Cabinet components first.' if cabinets.empty?
    bounds = cabinets.map do |cabinet|
      matrix = cabinet.transformation.to_a
      expected = [1,0,0,0, 0,1,0,0, 0,0,1,0]
      unless expected.each_with_index.all? { |value, index| (matrix[index] - value).abs < 0.000001 }
        raise ArgumentError, 'Worktop selection currently supports unrotated, unscaled cabinets only.'
      end
      box = cabinet.bounds
      [box.min.to_a.map { |v| v.to_f*25.4 }, box.max.to_a.map { |v| v.to_f*25.4 }]
    end.sort_by { |low, _high| low[0] }
    first_low, first_high = bounds.first
    bounds.each do |low, high|
      unless (high[2]-first_high[2]).abs <= 0.5 && (low[1]-first_low[1]).abs <= 0.5 && (high[1]-first_high[1]).abs <= 0.5
        raise ArgumentError, 'Select cabinets with the same top height, depth and front/rear alignment. Create separate worktops for different heights.'
      end
    end
    bounds.each_cons(2) do |(_left_low, left_high), (right_low, _right_high)|
      unless (right_low[0]-left_high[0]).abs <= 0.5
        raise ArgumentError, 'Selected cabinets must be adjacent without gaps or overlaps. Select each continuous run separately.'
      end
    end
    { 'x' => first_low[0], 'y' => first_low[1], 'z' => first_high[2],
      'width' => bounds.last[1][0] - first_low[0], 'depth' => first_high[1] - first_low[1] }
  end

  def validate_worktop(source)
    raise ArgumentError, 'Invalid worktop settings.' unless source.is_a?(Hash)
    c = source.dup
    c['name'] = c['name'].to_s.strip[0,80]
    c['name'] = 'Worktop' if c['name'].empty?
    c['material'] = c['material'].to_s.strip[0,60]
    c['material'] = 'MDF' if c['material'].empty?
    if c['material'].match?(/part|hardware/i)
      raise ArgumentError, 'Material name contains a CutList hardware keyword (part/hardware). Use a name such as MDF, Plywood or Chipboard.'
    end
    { 'thickness' => [6,100], 'front_overhang' => [0,300], 'rear_overhang' => [0,300],
      'left_overhang' => [0,300], 'right_overhang' => [0,300],
      'width' => [100,10000], 'depth' => [100,5000],
      'x' => [-1000000,1000000], 'y' => [-1000000,1000000], 'z' => [-1000000,1000000]
    }.each { |key, (low,high)| number_between!(c, key, low, high) }
    c
  end

  def worktop_geometry(c)
    { origin: [c['x']-c['left_overhang'], c['y']-c['front_overhang'], c['z']],
      size: [c['width']+c['left_overhang']+c['right_overhang'], c['depth']+c['front_overhang']+c['rear_overhang'], c['thickness']],
      stock: { name: "#{stock_number(c['thickness'])} mm #{c['material']} Worktop Sheet", base: [1.0,1.0,c['thickness']], type: 'sheet' } }
  end

  def cabinet_worktop_config(c)
    { 'name' => 'Cabinet worktop', 'material' => c['worktop_material'],
      'thickness' => c['worktop_thickness'], 'x' => 0, 'y' => -overlay_projection(c),
      'z' => case_height(c), 'width' => c['width'], 'depth' => c['depth'],
      'front_overhang' => c['worktop_front_overhang'], 'rear_overhang' => c['worktop_rear_overhang'],
      'left_overhang' => c['worktop_left_overhang'], 'right_overhang' => c['worktop_right_overhang'] }
  end

  def show_worktop_editor(instance = nil)
    model = Sketchup.active_model
    if instance
      config = validate_worktop(JSON.parse(instance.get_attribute(DICT, 'worktop_config')))
    else
      cabinets = model.selection.to_a
      unless cabinets.all? { |item| item.is_a?(Sketchup::ComponentInstance) && item.get_attribute(DICT, 'config').is_a?(String) }
        raise ArgumentError, 'Select only the adjacent Kero Cabinet components that need this worktop.'
      end
      if cabinets.any? { |cabinet| JSON.parse(cabinet.get_attribute(DICT, 'config'))['worktop'] == true }
        raise ArgumentError, 'Selected cabinets already include worktops. Disable their Create worktop setting before creating a shared top.'
      end
      config = worktop_footprint(cabinets).merge('name' => 'Worktop', 'material' => 'MDF',
        'thickness' => 30, 'front_overhang' => 0, 'rear_overhang' => 0, 'left_overhang' => 0, 'right_overhang' => 0)
    end
    keys = %w[name material thickness front_overhang rear_overhang left_overhang right_overhang]
    labels = ['Worktop name', 'Material name', 'Thickness (mm)', 'Front overhang (mm)', 'Rear overhang (mm)', 'Left overhang (mm)', 'Right overhang (mm)']
    values = UI.inputbox(labels, keys.map { |key| config[key] }, "Kero Cabinet | Worktop - #{stock_number(config['width'])} x #{stock_number(config['depth'])} mm")
    return unless values
    keys.zip(values).each { |key,value| config[key] = value }
    build_worktop(validate_worktop(config), instance)
  rescue StandardError => error
    UI.messagebox("Could not create or edit the worktop:\n#{error.message}")
  end

  def build_worktop(config, previous = nil)
    model = Sketchup.active_model
    model.start_operation(previous ? 'Edit Kero Cabinet worktop' : 'Create Kero Cabinet worktop', true)
    begin
      raise ArgumentError, 'The selected worktop no longer exists.' if previous && !previous.valid?
      geometry = worktop_geometry(config)
      part = box(model.active_entities, config['name'], geometry[:stock], *geometry[:origin], *geometry[:size], {})
      part.set_attribute(DICT, 'worktop_config', JSON.generate(config))
      obsolete = previous ? [previous.definition] : []
      previous.erase! if previous
      remove_unused_part_definitions(model, obsolete)
      model.selection.clear
      model.selection.add(part)
      model.commit_operation
      part
    rescue StandardError
      model.abort_operation
      raise
    end
  end

  def edit_selected_worktop
    selected = Sketchup.active_model.selection.to_a
    unless selected.length == 1 && selected.first.is_a?(Sketchup::ComponentInstance) && selected.first.get_attribute(DICT, 'worktop_config').is_a?(String)
      return UI.messagebox('Select one Kero Cabinet worktop component first.')
    end
    show_worktop_editor(selected.first)
  end

  def linked_cabinet?(instance)
    instance.definition.get_attribute(DICT, 'linked_cabinet') == true
  end

  def cabinet_config_raw(instance)
    shared = linked_cabinet?(instance) ? instance.definition.get_attribute(DICT, 'config') : nil
    shared.is_a?(String) ? shared : instance.get_attribute(DICT, 'config')
  end

  def create_linked_copy(source = nil)
    source ||= selected_cabinet
    raise ArgumentError, 'Select one Kero Cabinet component to create a linked copy.' unless source && source.valid?
    model = Sketchup.active_model
    model.start_operation('Create linked Kero Cabinet copy', true)
    begin
      raw = cabinet_config_raw(source)
      # Isolate from ordinary pre-existing copies before starting a linked family.
      source.make_unique unless linked_cabinet?(source)
      definition = source.definition
      definition.set_attribute(DICT, 'linked_cabinet', true)
      definition.set_attribute(DICT, 'config', raw)
      offset = Geom::Transformation.new([definition.bounds.width + mm(100), 0, 0])
      copy = model.active_entities.add_instance(definition, source.transformation * offset)
      copy.name = source.name
      copy.set_attribute(DICT, 'config', raw)
      copy.set_attribute(DICT, 'version', VERSION)
      model.selection.clear
      model.selection.add(copy)
      model.commit_operation
      copy
    rescue StandardError
      model.abort_operation
      raise
    end
  end

  def make_cabinet_independent(instance = nil)
    instance ||= selected_cabinet
    raise ArgumentError, 'Select one linked Kero Cabinet component first.' unless instance && instance.valid?
    return instance unless linked_cabinet?(instance)
    raw = cabinet_config_raw(instance)
    model = Sketchup.active_model
    model.start_operation('Make Kero Cabinet independent', true)
    begin
      instance.make_unique
      instance.definition.set_attribute(DICT, 'linked_cabinet', false)
      instance.definition.set_attribute(DICT, 'config', raw)
      instance.set_attribute(DICT, 'config', raw)
      model.commit_operation
      instance
    rescue StandardError
      model.abort_operation
      raise
    end
  end

  def linked_copy_command
    create_linked_copy
  rescue StandardError => error
    UI.messagebox(error.message)
  end

  def independent_copy_command
    make_cabinet_independent
  rescue StandardError => error
    UI.messagebox(error.message)
  end

  def selected_cabinet
    selection = Sketchup.active_model.selection
    return nil unless selection.length == 1
    item = selection.first
    return nil unless item.is_a?(Sketchup::ComponentInstance)
    return nil unless item.get_attribute(DICT, 'config').is_a?(String)
    item
  end

  def edit_selected
    cabinet = selected_cabinet
    return UI.messagebox('Select a Kero Cabinet component first.') unless cabinet
    show_dialog(cabinet)
  end

  # Walk reachable model entities, not unused component definitions or generated parts.
  def migration_targets(model)
    found={}
    visited={}
    walk=nil
    walk=lambda do |entities,blocked,path|
      entities.each do |item|
        next unless item.is_a?(Sketchup::ComponentInstance) || (defined?(Sketchup::Group) && item.is_a?(Sketchup::Group))
        locked=blocked || item.locked?
        cabinet=item.is_a?(Sketchup::ComponentInstance) && item.get_attribute(DICT,'config').is_a?(String)
        worktop=item.is_a?(Sketchup::ComponentInstance) && item.get_attribute(DICT,'worktop_config').is_a?(String)
        if cabinet || worktop
          entry=found[item] ||= {instance:item,kind:cabinet ? :cabinet : :worktop,locked:false}
          entry[:locked] ||= locked
          next
        end
        definition=item.definition
        next if path.include?(definition) || visited[[definition,locked]]
        visited[[definition,locked]]=true
        walk.call(definition.entities,locked,path+[definition])
      end
    end
    walk.call(model.entities,false,[])
    found.values
  end

  def prepare_migration(model=Sketchup.active_model)
    raise ArgumentError, 'Exit component/group editing before migrating the model.' if model.respond_to?(:active_path) && model.active_path
    targets=migration_targets(model)
    errors=[]
    jobs=[]
    linked={}
    targets.each do |target|
      item=target[:instance]
      begin
        raise ArgumentError, 'Object or containing group is locked. Unlock it before migration.' if target[:locked]
        if target[:kind]==:cabinet
          c=validate_config(JSON.parse(cabinet_config_raw(item)))
          generate_parts(nil,c,nil,preview:true)
          if linked_cabinet?(item)
            prior=linked[item.definition]
            if prior
              prior[:count]+=1
              next
            end
          end
          job={instance:item,kind: :cabinet,config:c,count:1}
          linked[item.definition]=job if linked_cabinet?(item)
          jobs << job
        else
          c=validate_worktop(JSON.parse(item.get_attribute(DICT,'worktop_config')))
          worktop_geometry(c)
          unless item.definition.get_attribute(DICT,'stock_key').to_s.start_with?('stock-v1:')
            raise ArgumentError, 'Unsupported worktop stock format. Edit this worktop separately before migration.'
          end
          jobs << {instance:item,kind: :worktop,config:c,count:1}
        end
      rescue StandardError => e
        errors << "#{item.name.to_s.empty? ? 'Unnamed Kero object' : item.name}: #{e.message}"
      end
    end
    raise ArgumentError,"Migration preflight failed. No model changes were made.\n\n#{errors.join("\n")}" unless errors.empty?
    {jobs:jobs,cabinets:targets.count { |t| t[:kind]==:cabinet },worktops:targets.count { |t| t[:kind]==:worktop }}
  end

  def migrate_worktop_stock(item,config,model)
    geometry=worktop_geometry(config)
    old=item.definition
    # Replacing only the canonical stock definition preserves the full placement
    # transform, including user moves/rotations/scales and nested parent context.
    temporary=box(model.entities,config['name'],geometry[:stock],*geometry[:origin],*geometry[:size],{})
    item.definition=temporary.definition
    item.material=temporary.material
    item.set_attribute(DICT,'worktop_config',JSON.generate(config))
    item.set_attribute(DICT,'version',VERSION)
    temporary.erase!
    remove_unused_part_definitions(model,[old])
  end

  def migrate_all(model=Sketchup.active_model,plan=nil)
    plan ||= prepare_migration(model)
    return plan if plan[:jobs].empty?
    selection=model.selection.to_a
    model.start_operation("Migrate all Kero Cabinets to #{VERSION}",true)
    begin
      plan[:jobs].each do |job|
        item=job[:instance]
        raise ArgumentError, 'A migration target is no longer available.' unless item.valid?
        if job[:kind]==:cabinet
          build_cabinet(job[:config],item,manage_operation:false,update_selection:false)
        else
          migrate_worktop_stock(item,job[:config],model)
        end
      end
      model.selection.clear
      model.selection.add(selection.select(&:valid?))
      model.commit_operation
    rescue StandardError
      model.abort_operation
      raise
    end
    plan
  end

  def migrate_all_command
    model=Sketchup.active_model
    return UI.messagebox('Close parameter/interior panels before migrating all objects.') if editors_open?
    plan=prepare_migration(model)
    return UI.messagebox('No Kero Cabinet objects were found in this model.') if plan[:jobs].empty?
    message="Regenerate #{plan[:cabinets]} cabinet instances and #{plan[:worktops]} independent worktops using Kero Cabinet #{VERSION}?\n\nLinked families are rebuilt once. Saved settings, placement and opening poses are preserved. New geometry rules may change part sizes. The whole migration can be undone in one step."
    return unless UI.messagebox(message,MB_OKCANCEL)==IDOK
    migrate_all(model,plan)
    UI.messagebox("Migration complete: #{plan[:cabinets]} cabinet instances and #{plan[:worktops]} worktops updated to #{VERSION}.")
  rescue StandardError => e
    UI.messagebox("Migration could not complete.\n#{e.message}")
  end

  def interior_groups(instance)
    c=JSON.parse(cabinet_config_raw(instance))
    groups=interior_groups_for_config(c)
    if c['double_sided']
      rear=interior_groups_for_config(c.merge('bays'=>c['rear_bays']))
      rear.each do |group|
        group['label']="Rear #{group['label']}"
        group['fronts']=group['fronts'].map { |name| "Rear #{name}" }
        group['tag']="Rear #{group['tag']}" if group['tag']
        group['rear']=true
      end
      groups.concat(rear)
    end
    groups
  end

  def interior_groups_for_config(c)
    groups=[]
    c['bays'].each_with_index do |bay,i|
      sections=bay['kind']=='stack' ? bay['sections'] : [bay]
      sections.each_with_index do |section,s|
        prefix=sections.length==1 ? "Bay #{i+1}" : "Bay #{i+1} section #{s+1}"
        label=sections.length==1 ? "Bay #{i+1}" : "Bay #{i+1} / #{s.zero? ? 'bottom' : s==sections.length-1 ? 'top' : "section #{s+1}"}"
        if section['kind']=='door'
          groups << { 'label'=>"#{label} - doors",'kind'=>'door','fronts'=>(1..section['doors']).map { |j| "#{prefix} door #{j}" } }
        elsif section['kind']=='drawer'
          section['drawers'].times { |j| groups << { 'label'=>"#{label} - drawer #{j+1}#{j.zero? ? ' (bottom)' : ''}",'kind'=>'drawer','tag'=>"#{prefix} drawer #{j+1}",'fronts'=>["#{prefix} drawer front #{j+1}"] } }
        end
      end
    end
    groups
  end

  def interior_hidden_fronts(definition)
    raw=definition.get_attribute(DICT,'interior_open_fronts')
    raw=definition.get_attribute(DICT,'interior_hidden_fronts') unless raw.is_a?(String)
    value=raw.is_a?(String) ? JSON.parse(raw) : []
    value.is_a?(Array) ? value.grep(String) : []
  rescue JSON::ParserError
    []
  end

  # Always rebuild the pose from the saved closed transform, never from the last pose.
  def apply_interior_visibility(instance)
    opened=interior_hidden_fronts(instance.definition)
    groups=interior_groups(instance)
    parts=instance.definition.entities.grep(Sketchup::ComponentInstance)
    names=groups.flat_map { |group| group['fronts'] }
    moving=parts.select { |part| interior_member?(part.name,groups) }
    moving.each do |part|
      closed=part.get_attribute(DICT,'closed_transform')
      unless closed.is_a?(Array) && closed.length==16
        closed=part.transformation.to_a
        part.set_attribute(DICT,'closed_transform',closed)
      end
      part.transformation=Geom::Transformation.new(closed)
      part.hidden=false if names.include?(part.name)
    end
    groups.each do |group|
      next unless group['fronts'].all? { |name| opened.include?(name) }
      if group['kind']=='drawer'
        side=parts.find { |part| part.name=="#{group['tag']} left side" }
        next unless side
        low,high=interior_bounds(side)
        shift=Geom::Transformation.new([0,(group['rear'] ? 1 : -1)*(high[1]-low[1])*0.9,0])
        parts.select { |part| part.name==group['fronts'].first || part.name.start_with?("#{group['tag']} ") }.each do |part|
          part.transformation=shift*part.transformation
        end
      else
        group['fronts'].each_with_index do |name,index|
          door=parts.find { |part| part.name==name }
          next unless door
          low,high=interior_bounds(door)
          right=group['fronts'].length>1 && index==group['fronts'].length-1
          hinge_right=group['rear'] ? !right : right
          pivot=[hinge_right ? high[0] : low[0],group['rear'] ? low[1] : high[1],low[2]]
          swing=Geom::Transformation.rotation(pivot,Z_AXIS,(right ? 1 : -1)*Math::PI/2)
          door.transformation=swing*door.transformation
        end
      end
    end
    instance.definition.set_attribute(DICT,'interior_open_fronts',JSON.generate(opened & names))
    instance.definition.set_attribute(DICT,'interior_hidden_fronts','[]')
  end

  def interior_bounds(part)
    [part.bounds.min.to_a,part.bounds.max.to_a]
  end

  def interior_member?(name,groups)
    groups.any? { |group| group['fronts'].include?(name) || (group['kind']=='drawer' && name.start_with?("#{group['tag']} ")) }
  end

  def set_interior_visibility(instance,index,show)
    raise ArgumentError, 'The cabinet is no longer available.' unless instance && instance.valid?
    groups=interior_groups(instance)
    unless %w[all refresh].include?(index) || (index.is_a?(Integer) && index>=0 && index<groups.length)
      raise ArgumentError, 'Select an available cabinet section.'
    end
    model=Sketchup.active_model
    model.start_operation('Show cabinet interior',true)
    begin
      instance.make_unique unless linked_cabinet?(instance)
      hidden=interior_hidden_fronts(instance.definition)
      names=index=='refresh' ? [] : index=='all' ? groups.flat_map { |group| group['fronts'] } : groups[index]['fronts']
      hidden=show ? hidden|names : hidden-names
      instance.definition.set_attribute(DICT,'interior_open_fronts',JSON.generate(hidden))
      apply_interior_visibility(instance)
      model.commit_operation
    rescue StandardError
      model.abort_operation
      raise
    end
  end

  def interior_view_html(groups,hidden,linked)
    initial=JSON.generate({'groups'=>groups,'hidden'=>hidden}).gsub('</','<\\/')
    <<~HTML
      <!doctype html><html lang="en"><head><meta charset="utf-8"><style>
      body{font:14px -apple-system,BlinkMacSystemFont,Arial,sans-serif;color:#253b30;background:#f5f6f1;padding:18px}h1{font-size:19px}p{font-size:12px;line-height:1.5;color:#66705e}.row{display:flex;gap:12px;align-items:center;background:white;border:1px solid #dce2d5;padding:14px;margin:8px 0;border-radius:8px}.row input{width:18px;height:18px}button{padding:10px;border:1px solid #bac8b2;border-radius:6px;background:white;color:#355e40;cursor:pointer}#error{color:#ae3429}
      </style></head><body><h1>Interior view</h1><p>Open individual sections. Drawers slide forward with their fronts, boxes and organizers. Doors swing 90 degrees from their outer hinge edges. Changes appear immediately and can be undone. This panel uses the saved cabinet layout; apply pending parameter edits first.</p>
      <p>#{linked ? 'Linked copies share this view state.' : 'This view applies only to the selected cabinet.'} Close all before measuring overall cabinet bounds or exporting the assembled model. Drawer travel is a preview at 90% of box depth; actual hardware stroke and hinge clearance are not simulated.</p>
      <button onclick="setAll(true)">Open all</button> <button onclick="setAll(false)">Close all</button><div id="groups"></div><p id="error"></p>
      <script>
      const initial=#{initial};
      function renderInterior(state){document.getElementById('groups').innerHTML=state.groups.map((g,i)=>'<label class="row"><input type="checkbox" '+(g.fronts.every(n=>state.hidden.includes(n))?'checked':'')+' onchange="setInterior('+i+',this.checked)"><span>'+g.label+'<br><small>Open</small></span></label>').join('')||'<p>This cabinet has no doors or drawer fronts.</p>';}
      function setInterior(index,show){window.sketchup.interior(JSON.stringify({index,show}));}
      function setAll(show){setInterior('all',show);}
      function interiorError(message){document.getElementById('error').textContent=message;}
      renderInterior(initial);
      </script></body></html>
    HTML
  end

  def show_interior_view(instance=nil)
    instance ||= selected_cabinet
    return UI.messagebox('Select a Kero Cabinet component first.') unless instance && instance.valid?
    if !instance.definition.get_attribute(DICT,'interior_open_fronts').is_a?(String) && !interior_hidden_fronts(instance.definition).empty?
      set_interior_visibility(instance,'refresh',false)
    end
    dialog=UI::HtmlDialog.new(dialog_title:'Kero Cabinet | Interior view',preferences_key:'KeroCabinet.InteriorView',scrollable:true,resizable:true,width:430,height:580,style:UI::HtmlDialog::STYLE_DIALOG)
    dialog.set_html(interior_view_html(interior_groups(instance),interior_hidden_fronts(instance.definition),linked_cabinet?(instance)))
    dialog.add_action_callback('interior') do |_context,raw|
      begin
        request=JSON.parse(raw)
        raise ArgumentError, 'Invalid interior switch value.' unless [true,false].include?(request['show'])
        set_interior_visibility(instance,request['index'],request['show'])
        state={'groups'=>interior_groups(instance),'hidden'=>interior_hidden_fronts(instance.definition)}
        dialog.execute_script("renderInterior(#{JSON.generate(state)});interiorError('')")
      rescue StandardError => e
        dialog.execute_script("interiorError(#{JSON.generate(e.message)})")
      end
    end
    @dialogs ||= []
    @dialogs << dialog
    dialog.set_on_closed { @dialogs.delete(dialog) }
    dialog.show
  end

  def dialog_html
    <<~'HTML'
      <!doctype html>
      <html lang="en">
      <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        * {box-sizing:border-box} body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;margin:0;background:#f5f4f1;color:#272727;font-size:13px}
        header{padding:20px 22px 15px;background:#242526;color:#fff} h1{font-size:20px;margin:0 0 4px}header p{margin:0;color:#c5c5c5}
        main{padding:18px 20px 85px}.section{background:white;border:1px solid #e3e1dc;border-radius:10px;padding:16px;margin-bottom:13px}
        h2{font-size:14px;margin:0 0 12px} .grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}
        .grid.two{grid-template-columns:repeat(2,minmax(0,1fr))}label{display:block;font-size:11px;font-weight:600;color:#565656;margin-bottom:4px}
        input,select{width:100%;height:34px;border:1px solid #d4d1cc;background:white;border-radius:6px;padding:6px;font-size:13px;color:#222}
        input[type=checkbox]{width:17px;height:17px;accent-color:#84613e} .check{display:flex;align-items:center;gap:8px;margin:12px 0 0}
        .check label{margin:0}.hint{font-size:11px;color:#707070;line-height:1.45;margin:9px 0 0}
        .construction-options{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
        .construction-option{display:block;position:relative;cursor:pointer;margin:0}
        .construction-option input{position:absolute;opacity:0;width:1px;height:1px}
        .construction-card{height:100%;border:2px solid #dedbd4;border-radius:10px;background:#faf9f7;padding:12px;text-align:center;display:flex;align-items:center;flex-direction:column;gap:5px}
        .construction-card svg{display:block;width:100%;max-width:168px;height:126px}
        .construction-option input:checked+.construction-card{border-color:#3c7354;background:#eef6f0}
        .construction-option input:focus-visible+.construction-card{outline:3px solid #78a28a;outline-offset:2px}
        .construction-card strong{font-size:13px;color:#262626}
        .construction-card small{color:#666;font-size:11px;line-height:1.3}
        .bay{background:#faf9f7;border:1px solid #e7e4df;border-radius:8px;padding:12px;margin:8px 0}
        .bayhead{display:flex;justify-content:space-between;align-items:center;margin:0 0 10px;font-weight:700}
        .ghost{background:#fff;color:#555;border:1px solid #d2cec9;border-radius:6px;padding:8px 10px;cursor:pointer}
        .remove{font-size:12px;padding:4px 9px}.actions{position:fixed;bottom:0;left:0;right:0;padding:12px 20px;background:#fff;border-top:1px solid #ddd;display:flex;align-items:center;gap:12px}
        .primary{background:#3c7354;color:#fff;border:0;border-radius:7px;padding:12px 18px;font-weight:700;cursor:pointer}
        .error{color:#ae3429;flex:1;font-size:12px;overflow-wrap:anywhere}.spacer{flex:1}
        @media(max-width:560px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}

        button:disabled{opacity:.4;cursor:default}.bay{background:#fff;padding:14px;border-color:#dedfd9}.bayhead{font-size:14px}.bay-subtitle{font-size:11px;color:#73776e;font-weight:400;margin-top:3px}
        .type-picker{display:flex;gap:4px;background:#f1f2ed;padding:4px;border-radius:8px;flex-wrap:wrap;margin:10px 0 12px}.type-picker button{flex:1;border:0;border-radius:5px;padding:8px 6px;background:transparent;color:#60665a;font-size:12px;cursor:pointer;white-space:nowrap}.type-picker button.active{background:#fff;color:#285e40;box-shadow:0 1px 4px #0002;font-weight:700}.type-picker button:focus-visible,.preset:focus-visible{outline:2px solid #3c7354;outline-offset:2px}
        .layout-tools{display:flex;gap:6px;align-items:center;flex-wrap:wrap;margin:12px 0}.layout-tools span{font-size:11px;color:#73776e}.preset{border:1px solid #d7dcd2;border-radius:6px;background:#f7f9f4;padding:7px 8px;cursor:pointer;font-size:11px;color:#40583e}.section-layout{display:grid;grid-template-columns:76px minmax(0,1fr);gap:12px;align-items:start}.cabinet-preview{display:flex;flex-direction:column;border:3px solid #c4b598;border-radius:3px;background:#e9e2d5;min-height:210px;overflow:hidden}.preview-cell{border:0;border-bottom:2px solid #c4b598;background:#eee8dc;color:#5d5343;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:9px 2px;font-size:10px;min-height:35px;gap:4px}.preview-cell:last-child{border-bottom:0}.preview-cell.drawer{background:#ded2ba}.preview-cell.open{background:#f8f5ed}.preview-cell strong{font-size:11px}.stack-item{border:1px solid #e1e4da;border-left:3px solid #91a684;border-radius:8px;padding:12px;margin-bottom:10px;scroll-margin-top:15px;background:#fafbf8}.stack-head{display:flex;justify-content:space-between;align-items:center;gap:5px}.stack-title{font-size:12px;font-weight:700}.position-tag{font-size:10px;letter-spacing:.06em;text-transform:uppercase;color:#7d8575;display:block;margin-bottom:3px}.stack-actions{display:flex;gap:3px}.stack-actions button{border:1px solid #dce0d5;background:#fff;border-radius:5px;padding:5px 7px;cursor:pointer;font-size:12px}.stack-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:9px}.share-line{display:flex;align-items:center;justify-content:space-between;gap:5px;margin-bottom:4px}.share-line label{margin:0}.share-badge{font-size:11px;font-weight:700;color:#3c7354}.add-section{width:100%;padding:10px;border:1px dashed #a7b89d;border-radius:6px;background:#f6f9f2;color:#405b35;cursor:pointer}.bay-width{display:flex;align-items:center;gap:10px;padding:8px 0}.bay-width label{margin:0;white-space:nowrap}.bay-width input{max-width:95px}.bay-width span{font-size:11px;color:#73776e}.section-intro{font-size:11px;line-height:1.5;color:#6c7364;margin:8px 0 12px}@media(max-width:520px){.section-layout{grid-template-columns:1fr}.cabinet-preview{display:none}.type-picker button{font-size:11px}.stack-actions button{padding:5px}}

        [hidden]{display:none!important}body{background:#f1f2ee;color:#253027}.editor-header{display:flex;justify-content:space-between;align-items:center;gap:12px;background:#253b30;padding:18px 22px}.editor-header h1{font-size:19px;letter-spacing:-.3px}.editor-header p{font-size:12px;color:#c7d4c7}.version-tag{font-size:11px;white-space:nowrap;color:#d7e4d5;border:1px solid #617463;border-radius:20px;padding:5px 9px}.editor-tabs{display:grid;grid-template-columns:1.3fr 1fr 1fr .8fr 1fr;gap:5px;padding:10px 18px;background:#f8f9f5;border-bottom:1px solid #dce2d5;position:sticky;top:0;z-index:5}.editor-tabs button{border:0;background:transparent;border-radius:7px;color:#697465;padding:10px 5px;font-size:12px;font-weight:600;cursor:pointer}.editor-tabs button[aria-selected=true]{background:#fff;color:#264d35;box-shadow:0 1px 5px #1a30251a}.editor-tabs button:focus-visible{outline:2px solid #68865c;outline-offset:1px}main{padding:16px 18px 130px}.section{border-color:#dfe5d8;border-radius:12px;padding:18px;margin-bottom:14px}.section h2{font-size:14px;letter-spacing:-.1px;margin-bottom:16px}.grid{gap:13px}.name-field{grid-column:1/-1}label{font-size:11px;color:#626d5c}input,select{border-color:#d4ddcc;border-radius:7px;height:38px;background:#fff}input:focus,select:focus{outline:2px solid #b5c9a8;outline-offset:1px}.advanced{border-top:1px solid #e5e9df;margin-top:16px;padding-top:12px}.advanced>summary{cursor:pointer;color:#49613d;font-size:12px;font-weight:600;margin-bottom:12px}.help-details{margin-top:12px}.help-details>summary{font-size:11px;color:#788471;cursor:pointer}.help-details .hint{background:#f6f8f2;padding:10px;border-radius:7px}.construction-card svg{height:72px;max-width:110px}.construction-card{padding:10px}.construction-card small{font-size:10px}.actions{padding:10px 18px 13px;display:block;z-index:10;box-shadow:0 -3px 16px #253b3009;border-color:#dce4d3}.editor-summary{font-size:11px;line-height:1.5;color:#67765e;padding:0 0 8px;border-bottom:1px solid #edf0e8;margin-bottom:9px}.action-row{display:flex;align-items:center;justify-content:space-between;gap:12px}.error{font-size:11px;max-height:64px;overflow:auto}.primary{white-space:nowrap;padding:12px 22px;background:#355e40}.check{background:#f4f7ef;padding:10px;border-radius:7px}.stack-item{background:#fafbf7}.bay{border-color:#dde5d5}.preset{background:#f5f8ef}.type-picker{background:#edf2e6}@media(max-width:540px){.editor-header{padding:14px}.editor-header p{max-width:230px;font-size:11px}.editor-tabs{padding:8px 10px;gap:2px}.editor-tabs button{font-size:11px}main{padding:12px 10px 140px}.section{padding:14px}.actions{padding:9px 12px}.primary{padding:11px 16px}.version-tag{font-size:10px}}
        .linked-notice{margin:0;padding:10px 20px;background:#fff3d8;color:#75551d;font-size:12px;line-height:1.45}
      </style>
      </head>
      <body>
      <header class="editor-header"><div><h1>Kero Cabinet</h1><p>Design your cabinet. Fine-tune only what you need.</p></div><span class="version-tag">v0.22.1 &middot; mm</span></header>
      <p id="linked-notice" class="linked-notice" hidden></p>
      <nav class="editor-tabs" role="tablist" aria-label="Cabinet settings">
        <button id="tab-size" type="button" role="tab" data-tab="size" aria-controls="panel-size" aria-selected="true" onclick="showTab('size')">Size &amp; fronts</button>
        <button id="tab-layout" type="button" role="tab" data-tab="layout" aria-controls="panel-layout" aria-selected="false" tabindex="-1" onclick="showTab('layout')">Layout</button>
        <button id="tab-build" type="button" role="tab" data-tab="build" aria-controls="panel-build" aria-selected="false" tabindex="-1" onclick="showTab('build')">Build</button>
        <button id="tab-base" type="button" role="tab" data-tab="base" aria-controls="panel-base" aria-selected="false" tabindex="-1" onclick="showTab('base')">Base</button>
        <button id="tab-worktop" type="button" role="tab" data-tab="worktop" aria-controls="panel-worktop" aria-selected="false" tabindex="-1" onclick="showTab('worktop')">Worktop</button>
      </nav>
      <main>
<div id="panel-size" role="tabpanel" data-panel="size" aria-labelledby="tab-size"><section class="section">
          <h2>Overall size</h2>
          <div class="grid">
            <div class="name-field"><label for="name">Cabinet name</label><input id="name" type="text" style="min-width:0"></div>
            <div><label for="width">Width (mm)</label><input id="width" type="number" step="1"></div>
            <div><label for="height">Overall height (mm)</label><input id="height" type="number" step="1"></div>
            <div><label for="depth">Overall depth (mm)</label><input id="depth" type="number" step="1"></div>
          </div>
          <details class="help-details"><summary>How this works</summary><p class="hint">Depth includes the back and any overlay fronts. The case is shortened to keep the requested overall depth. Overall height includes the selected base and any enabled worktop. Minimum total height is 100 mm; select No base and suitable panel/front settings for shallow custom builds.</p></details>
        </section><section class="section">
          <h2>Front style</h2>
          <div class="grid two">
            <div><label for="style">Door placement</label><select id="style"><option value="inset">Inset</option><option value="overlay">Overlay</option></select></div>
          </div>
          <div class="check"><input id="frame" type="checkbox" onchange="updateFrame()"><label for="frame">Create face frame</label></div>
        <details class="advanced"><summary>Face frame dimensions</summary><div class="grid two"><div><label for="frame_width">Face frame width (mm)</label><input id="frame_width" type="number" step="1"></div><div><label for="frame_depth">Face frame thickness (mm)</label><input id="frame_depth" type="number" step="1"></div></div></details></section></div>
<div id="panel-layout" role="tabpanel" data-panel="layout" aria-labelledby="tab-layout" hidden><section class="section">
          <h2>Cabinet layout</h2>
          <p class="hint" style="margin:0 0 10px">Add bays from left to right. Choose their contents, then split a bay into stacked sections when you need drawers below doors.</p>
          <section class="section"><h2>Cabinet access</h2><div class="check"><input id="double_sided" type="checkbox" onchange="updateAccess()"><label for="double_sided">Double-sided cabinet</label></div>
          <div id="double-options" hidden><div class="grid two"><div><label for="front_depth_share">Front share of usable depth (%)</label><input id="front_depth_share" type="number" min="10" max="90" value="50"></div><div><label for="layout_face">Edit layout</label><select id="layout_face" onchange="switchLayoutFace(this.value)"><option value="front">Front</option><option value="rear">Rear</option></select></div></div><p class="hint">Independent boxes on each face. A case-stock center partition separates them. Share applies after both overlay fronts and the partition. Back panel settings are replaced by this partition. Rear bays are shown left to right when standing behind the cabinet.</p></div><p id="layout-face-label" class="hint">Front layout</p></section>
          <div id="bays"></div>
          <button class="ghost" onclick="addBay()" type="button">+ Add bay</button>
        </section></div>
<div id="panel-build" role="tabpanel" data-panel="build" aria-labelledby="tab-build" hidden><section class="section"><h2>Material thicknesses</h2><div class="grid two"><div><label for="panel">Case panel (mm)</label><input id="panel" type="number" step="1"></div><div><label for="back">Back panel (mm)</label><input id="back" type="number" step="1"></div><div><label for="front">Door/front thickness (mm)</label><input id="front" type="number" step="1"></div><div><label for="gap">Front gap (mm)</label><input id="gap" type="number" step="0.5"></div></div><details class="help-details"><summary>How this works</summary><p class="hint">Shared Sheet stock is grouped by thickness. Front gap is the visible space between fronts.</p></details></section><section class="section">
          <h2>Top / Bottom / Back construction</h2>
          <div class="grid">
            <div><label for="top_construction">Top construction</label><select id="top_construction" onchange="updateConstruction()"><option value="full">Full panel</option><option value="rails">Support rails</option></select></div>
            <div><label for="bottom_construction">Bottom construction</label><select id="bottom_construction"><option value="between">Between sides</option><option value="full">Full width</option></select></div>
            <div><label for="back_construction">Back construction</label><select id="back_construction" onchange="updateConstruction()"><option value="full">Full panel</option><option value="rails">Support rails</option></select></div>
            <div><label for="rail_width">Rail width (mm)</label><input id="rail_width" type="number" min="40" max="200"></div>
          </div>
          <details class="help-details"><summary>How this works</summary><p class="hint">Support rails use the case material and thickness. Rails extend the sides to the cabinet top. A full-width bottom sits under the sides. With back rails, no external back thickness is deducted from the overall depth.</p></details>
<details class="advanced"><summary>Top panel placement</summary>          <h3>Top panel arrangement</h3>
          <div class="construction-options" role="radiogroup" aria-label="Case construction">
            <label class="construction-option">
              <input type="radio" name="construction" value="sides_full">
              <span class="construction-card">
                <svg viewBox="0 0 190 140" role="img" aria-label="Full-height side panels; shorter top and bottom panels">
                  <rect x="18" y="11" width="154" height="118" rx="2" fill="#faf6eb" stroke="#9c917d" stroke-width="2"/>
                  <rect x="18" y="11" width="20" height="118" fill="#4f8f70" stroke="#326b51" stroke-width="1.5"/>
                  <rect x="152" y="11" width="20" height="118" fill="#4f8f70" stroke="#326b51" stroke-width="1.5"/>
                  <rect x="38" y="11" width="114" height="20" fill="#d9b985" stroke="#92794e" stroke-width="1.5"/>
                  <rect x="38" y="109" width="114" height="20" fill="#d9b985" stroke="#92794e" stroke-width="1.5"/>
                </svg>
                <strong>Top between sides</strong>
                <small>Top fits between the sides; bottom is selected separately</small>
              </span>
            </label>
            <label class="construction-option">
              <input type="radio" name="construction" value="top_bottom_full">
              <span class="construction-card">
                <svg viewBox="0 0 190 140" role="img" aria-label="Full-width top and bottom panels; shorter side panels">
                  <rect x="18" y="11" width="154" height="118" rx="2" fill="#faf6eb" stroke="#9c917d" stroke-width="2"/>
                  <rect x="18" y="11" width="154" height="20" fill="#4f8f70" stroke="#326b51" stroke-width="1.5"/>
                  <rect x="18" y="109" width="154" height="20" fill="#4f8f70" stroke="#326b51" stroke-width="1.5"/>
                  <rect x="18" y="31" width="20" height="78" fill="#d9b985" stroke="#92794e" stroke-width="1.5"/>
                  <rect x="152" y="31" width="20" height="78" fill="#d9b985" stroke="#92794e" stroke-width="1.5"/>
                </svg>
                <strong>Full-width top</strong>
                <small>Sides fit under the top; bottom is selected separately</small>
              </span>
            </label>
          </div>
          <details class="help-details"><summary>How this works</summary><p class="hint">Top arrangement is locked when support rails are selected. Bottom construction stays independent. A full-width bottom raises the side start by its thickness without changing overall height.</p></details>
        </details></section><section class="section">
          <h2>Drawer construction</h2>
          <div class="grid two" style="margin-bottom:12px">
            <div><label for="drawer_height_mode">Drawer box height</label><select id="drawer_height_mode" onchange="updateDrawerHardware()"><option value="fit">Fit available height</option><option value="limit">Limit height</option></select></div>
            <div><label for="drawer_height_limit">Maximum box height (mm)</label><input id="drawer_height_limit" type="number" min="25" max="3000" step="1"></div>
          </div>
          <details class="help-details"><summary>How this works</summary><p class="hint">Fit fills the available height after hardware clearances. Limit caps box height and still shrinks it to fit smaller openings. Front dimensions stay unchanged. Applies to all drawers.</p></details>
          <div style="margin-bottom:12px"><label for="drawer_slide">Drawer hardware</label><select id="drawer_slide" onchange="updateDrawerHardware()"><optgroup label="Side mount"><option value="side_48">Side mount - Easy-close / 47.7 mm min. box</option><option value="side_35">Side mount - Low-profile / 35.1 mm min. box</option></optgroup><optgroup label="Undermount"><option value="undermount_563h">Undermount - Blum TANDEM 563H reference</option></optgroup></select></div>
          <div style="margin-bottom:12px"><label for="undermount_length">Undermount drawer length (mm)</label><select id="undermount_length"><option value="0">Auto - longest fitting</option><option>229</option><option>305</option><option>381</option><option>457</option><option>533</option></select></div>
          <div style="margin-bottom:12px"><label for="drawer_rear_gap">Side-mount rear clearance (mm)</label><input id="drawer_rear_gap" type="number" min="3" max="50" step="1"></div>
          <details class="help-details"><summary>How this works</summary><p class="hint">Auto chooses the longest supported TANDEM length that fits. This reference supports up to 533 mm, so deeper cabinets can retain unused rear space. Saved manual lengths stay fixed; select Auto to recalculate.</p></details>
          <p id="hardware_hint" class="hint"></p>
          <div class="grid two">
            <div><label for="drawer_thickness">Drawer box thickness (mm)</label><input id="drawer_thickness" type="number" min="6" max="30"></div>
            <div><label for="drawer_bottom">Drawer bottom thickness (mm)</label><input id="drawer_bottom" type="number" min="3" max="24"></div>
          </div>
          <details class="help-details"><summary>How this works</summary><p class="hint">Box sides and front/back members share the box thickness. The bottom fits between them. Visible drawer fronts use Door/front thickness. Outer box width follows the selected slide side clearance. Shallow box heights adapt to the opening.</p></details>
        </section></div>
<div id="panel-base" role="tabpanel" data-panel="base" aria-labelledby="tab-base" hidden><section class="section"><h2>Base</h2><label for="base_type">Base type</label><select id="base_type" onchange="updateToeKick()"><option value="none">No base</option><option value="timber">Timber toe kick</option><option value="casters">Casters</option></select><p class="hint">Overall height includes the selected base and any enabled worktop. No base starts the cabinet at floor level.</p></section><div id="timber-base"><section class="section">
          <h2>Toe kick</h2>
          <div class="grid two">
            <div><label for="toe">Toe kick height (mm)</label><input id="toe" type="number" step="1"></div>
          </div>
          <div class="check"><input id="toe_frame" type="checkbox" onchange="updateToeKick()"><label for="toe_frame">Create timber support frame</label></div>
          <div id="timber-fields" class="grid two" style="margin-top:10px">
            <div><label for="timber_height">Upright timber height (mm)</label><input id="timber_height" type="number" min="20" max="200"></div>
            <div><label for="timber_thickness">Timber thickness (mm)</label><input id="timber_thickness" type="number" min="10" max="100"></div>
          </div>
          <details class="help-details"><summary>How this works</summary><p class="hint">Default: 50 x 100 mm timber with 100 mm upright. Butt joints, full-width front/rear rails and cross rails at bay boundaries, with extra rails for spans over 600 mm. The front panel spans the full cabinet width. The frame sits behind the toe kick front; taller toe spaces receive legs. No frame is created at zero toe height.</p></details>
        </section></div><section class="section" id="caster-fields" hidden><h2>Casters</h2><div class="grid two">
          <div><label for="caster_height">Mounting height (mm)</label><input id="caster_height" type="number" min="35" max="400"></div>
          <div><label for="caster_diameter">Wheel diameter (mm)</label><input id="caster_diameter" type="number" min="20" max="250"></div>
          <div><label for="caster_inset">Plate edge inset (mm)</label><input id="caster_inset" type="number" min="0" max="150"></div></div>
          <div class="check"><input id="caster_front_brakes" type="checkbox"><label for="caster_front_brakes">Front two casters with brakes</label></div>
          <p class="hint">Four representative corner casters. Mounting height is plate-to-floor, not wheel diameter. Plates sit under the bottom panel. No toe kick panel or timber frame is generated. Confirm the actual product footprint, mounting strength and load rating; drilling and movement are not modeled.</p></section></div><div id="panel-worktop" role="tabpanel" data-panel="worktop" aria-labelledby="tab-worktop" hidden><section class="section">
          <h2>Worktop</h2>
          <div class="check"><input id="worktop" type="checkbox" onchange="updateWorktop()"><label for="worktop">Create worktop for this cabinet</label></div>
          <div id="worktop-fields" class="grid two" style="margin-top:12px">
            <div><label for="worktop_thickness">Worktop thickness (mm)</label><input id="worktop_thickness" type="number" min="6" max="100"></div>
            <div><label for="worktop_material">Worktop material</label><input id="worktop_material" type="text" maxlength="60"></div>
            <div><label for="worktop_front_overhang">Front overhang (mm)</label><input id="worktop_front_overhang" type="number" min="0" max="300"></div>
            <div><label for="worktop_rear_overhang">Rear overhang (mm)</label><input id="worktop_rear_overhang" type="number" min="0" max="300"></div>
            <div><label for="worktop_left_overhang">Left overhang (mm)</label><input id="worktop_left_overhang" type="number" min="0" max="300"></div>
            <div><label for="worktop_right_overhang">Right overhang (mm)</label><input id="worktop_right_overhang" type="number" min="0" max="300"></div>
          </div>
          <details class="help-details"><summary>How this works</summary><p class="hint">Default: 30 mm MDF, separate Worktop Sheet material. Follows this cabinet when regenerated. Thickness is included in Overall height; the case is shortened accordingly. Overhangs add to outside width/depth. Does not replace the structural top panel or remove manually modeled tops. For neighboring cabinets, leave side overhangs at zero to avoid overlap.</p></details>
        </section></div>
      </main>
      <div class="actions"><div class="editor-summary" id="editor-summary" aria-live="polite"></div><div class="action-row"><span class="error" id="error" role="alert"></span><button type="button" onclick="window.sketchup.interior_view()">Interior view...</button><button class="primary" type="button" onclick="submitConfig()">Apply to model</button></div></div>
      <script>
        const initial = /* INITIAL_CONFIG */ null;
        const linkedCount=initial._linked_count||0;
        document.getElementById('linked-notice').hidden=linkedCount<1;
        document.getElementById('linked-notice').textContent=`Linked cabinet: Apply to model updates all ${linkedCount} linked copies. Positions stay separate. Reopen other editors after applying to avoid stale settings.`;
        let frontBays=JSON.parse(JSON.stringify(initial.bays));
        let rearBays=JSON.parse(JSON.stringify(initial.rear_bays));
        let activeFace='front';
        let bays=frontBays;
        document.getElementById('double_sided').checked=!!initial.double_sided;
        document.getElementById('front_depth_share').value=initial.front_depth_share;
        function switchLayoutFace(face){activeFace=face;bays=face==='rear'?rearBays:frontBays;organizerFits={};organizerRevision++;renderBays();document.getElementById('layout-face-label').textContent=face==='rear'?'Rear layout':'Front layout';}
        function updateAccess(){const enabled=document.getElementById('double_sided').checked;document.getElementById('double-options').hidden=!enabled;document.getElementById('front_depth_share').disabled=!enabled;document.getElementById('layout_face').disabled=!enabled;document.getElementById('back_construction').disabled=enabled;document.getElementById('back').disabled=enabled;if(!enabled){document.getElementById('layout_face').value='front';switchLayoutFace('front');}updateConstruction();}
        function organizerKey(i,s,j){return (activeFace==='rear'?'rear:':'')+`${i}:${s}:${j}`;}

        const ids = ['name','width','height','depth','panel','back','front','toe','gap','style','frame_width','frame_depth','timber_height','timber_thickness','top_construction','bottom_construction','back_construction','rail_width','drawer_thickness','drawer_bottom','drawer_slide','undermount_length','drawer_rear_gap','drawer_height_mode','drawer_height_limit','worktop_thickness','worktop_material','worktop_front_overhang','worktop_rear_overhang','worktop_left_overhang','worktop_right_overhang','base_type','caster_height','caster_diameter','caster_inset'];
        for (const id of ids) document.getElementById(id).value = initial[id];
        document.getElementById('frame').checked = !!initial.frame;
        document.getElementById('toe_frame').checked = !!initial.toe_frame;
        document.getElementById('worktop').checked = !!initial.worktop;
        document.getElementById('caster_front_brakes').checked = !!initial.caster_front_brakes;
        (document.querySelector('input[name=construction][value="'+(initial.construction||'sides_full')+'"]') || document.querySelector('input[name=construction][value=sides_full]')).checked = true;
        const n = (v) => Number(v);
        const escapeHtml = (s) => String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/"/g,'&quot;');
        function updateConstruction(){
          const rails=document.getElementById('top_construction').value==='rails'||(!document.getElementById('double_sided').checked&&document.getElementById('back_construction').value==='rails');
          if(rails) document.querySelector('input[name=construction][value=sides_full]').checked=true;
          for(const radio of document.querySelectorAll('input[name=construction]')) radio.disabled=rails;
          document.getElementById('rail_width').disabled=!rails;
          document.getElementById('back').disabled=document.getElementById('double_sided').checked||document.getElementById('back_construction').value==='rails';
        }
        function updateDrawerHardware(){
          document.getElementById('drawer_height_limit').disabled=document.getElementById('drawer_height_mode').value!=='limit';
          const under=document.getElementById('drawer_slide').value==='undermount_563h';
          document.getElementById('undermount_length').disabled=!under;
          document.getElementById('drawer_rear_gap').disabled=under;
          document.getElementById('hardware_hint').textContent=under?'TANDEM reference: 12-16 mm sides; inside width = opening minus 42 mm; 13 mm recessed bottom; 14 mm below and 6 mm above the box. Front/back members are raised to leave the underside open. Hook holes, exact rear notches, locking devices and hardware models are not generated; prepare them using the manufacturer template.':'Side-mount height and side-space references. Kero Cabinet reserves 4 mm above and below the box. Check actual length, width limits, mounting and holes against the hardware datasheet.';
        }
        function updateToeKick(){
          const mode=document.getElementById('base_type').value;
          document.getElementById('timber-base').hidden=mode!=='timber';
          document.getElementById('caster-fields').hidden=mode!=='casters';
          document.getElementById('toe').disabled=mode!=='timber';document.getElementById('toe_frame').disabled=mode!=='timber';
          for(const id of ['caster_height','caster_diameter','caster_inset','caster_front_brakes'])document.getElementById(id).disabled=mode!=='casters';
          const enabled=mode==='timber'&&document.getElementById('toe_frame').checked&&Number(document.getElementById('toe').value)>0;
          document.getElementById('timber-fields').hidden=!enabled;
          for(const id of ['timber_height','timber_thickness'])document.getElementById(id).disabled=!enabled;
        }
        function updateWorktop(){
          document.getElementById('worktop-fields').hidden=!document.getElementById('worktop').checked;
          for(const id of ['worktop_thickness','worktop_material','worktop_front_overhang','worktop_rear_overhang','worktop_left_overhang','worktop_right_overhang']) document.getElementById(id).disabled=!document.getElementById('worktop').checked;
        }
        function updateFrame(){
          for(const id of ['frame_width','frame_depth']) document.getElementById(id).disabled = !document.getElementById('frame').checked;
        }
        function addBay(){
          if(bays.length>=6) return showError('You can add up to 6 bays.');
          bays.push({kind:'door',weight:1,doors:1,drawers:4,shelves:1}); renderBays();
        }
        function moveBay(i,direction){const target=i+direction;if(target<0||target>=bays.length)return;[bays[i],bays[target]]=[bays[target],bays[i]];organizerFits={};organizerRevision++;renderBays();}
        function removeBay(i){ if(bays.length>1){bays.splice(i,1);renderBays();} }
        function newSection(kind='door',weight=1){return {kind,weight,doors:1,drawers:1,shelves:1};}
        function changeBay(i,key,value){
          bays[i][key]=key==='kind'?value:Number(value);
          if(key==='drawers')renderBays();
          if(key==='kind'){
            if(value==='stack'&&!bays[i].sections)bays[i].sections=[newSection('drawer',1),newSection('door',3)];
            renderBays();
          }
        }
        function changeSection(i,j,key,value){bays[i].sections[j][key]=key==='kind'?value:Number(value);if(key==='kind'||key==='drawers')renderBays();}
        function addSection(i){if(bays[i].sections.length>=6)return showError('A bay supports up to 6 stacked sections.');bays[i].sections.push(newSection());renderBays();}
        function removeSection(i,j){if(bays[i].sections.length>2){bays[i].sections.splice(j,1);renderBays();}}
        function moveSection(i,j,direction){const items=bays[i].sections;const target=j+direction;if(target>=0&&target<items.length){[items[j],items[target]]=[items[target],items[j]];renderBays();}}
        const kindNames={door:'Doors',drawer:'Drawers',open:'Open shelves',stack:'Mixed layout'};
        function typePicker(kind,action,stack=false){
          return `<div class="type-picker" role="group" aria-label="Contents">${(stack?['door','drawer','open','stack']:['door','drawer','open']).map(value=>`<button type="button" class="${kind===value?'active':''}" aria-pressed="${kind===value}" onclick="${action.replace('VALUE',value)}">${kindNames[value]}</button>`).join('')}</div>`;
        }
        function layoutPreset(i,name){
          bays[i].kind='stack';
          bays[i].sections=name==='three'?[newSection('drawer',1),newSection('open',1),newSection('door',2)]:[newSection('drawer',1),newSection('door',name==='equal'?1:3)];
          renderBays();
        }
        function refreshLayout(){renderBays();}
        let organizerFits={};
        let organizerRevision=0;
        function organizerItem(i,s){return s<0?bays[i]:bays[i].sections[s];}
        function organizerDefault(){return {type:'none',layout:'grid',thickness:6,material:'Plywood',columns:'1 1 1',rows:'1 1',height:0,clearance:1,align:'center',bins:[]};}
        function organizerAt(i,s,j){const item=organizerItem(i,s);return Object.assign(organizerDefault(),(item.organizers||[])[j]||{});}
        function storeOrganizer(i,s,j,o){const item=organizerItem(i,s);if(!item.organizers)item.organizers=[];while(item.organizers.length<=j)item.organizers.push(organizerDefault());item.organizers[j]=o;organizerFits={};organizerRevision++;}
        function changeOrganizer(i,s,j,key,value){const o=organizerAt(i,s,j);o[key]=['thickness','height','clearance'].includes(key)?Number(value):value;storeOrganizer(i,s,j,o);renderBays();}
        function copyOrganizer(i,s,j){const item=organizerItem(i,s),o=organizerAt(i,s,j);item.organizers=Array.from({length:Number(item.drawers)},()=>JSON.parse(JSON.stringify(o)));organizerFits={};organizerRevision++;renderBays();}
        function changeOrganizerBin(i,s,j,index,key,value){const o=organizerAt(i,s,j);o.bins[index][key]=Number(value);storeOrganizer(i,s,j,o);renderBays();}
        function removeOrganizerBin(i,s,j,index){const o=organizerAt(i,s,j);o.bins.splice(index,1);storeOrganizer(i,s,j,o);renderBays();}
        function addOrganizerBin(i,s,j){
          const o=organizerAt(i,s,j);if(o.bins.length>=64)return showError('Gridfinity supports up to 64 bins per drawer.');
          const fit=organizerFits[organizerKey(i,s,j)],cols=fit?.columns||12,rows=fit?.rows||12;
          for(let y=1;y<=rows;y++)for(let x=1;x<=cols;x++)if(!o.bins.some(b=>x>=b.x&&x<b.x+b.w&&y>=b.y&&y<b.y+b.d)){
            o.bins.push({x,y,w:1,d:1,h:Math.max(1,Math.min(3,fit?.max_height_units??3))});storeOrganizer(i,s,j,o);renderBays();return;
          }
          showError('Gridfinity has no free cell for another bin.');
        }
        function requestOrganizerPreview(){const c=collectConfig();if(!c)return;if(!window.sketchup?.organizer_preview)return showError('Organizer fit preview is available inside SketchUp.');window.sketchup.organizer_preview(JSON.stringify({config:c,version:organizerRevision}));}
        function receiveOrganizerPreview(rows,version){if(version!==organizerRevision)return;organizerFits={};for(const row of rows)organizerFits[row.key]=row.plan;renderBays();}
        function organizerDiagram(plan){
          const w=plan.width,d=plan.depth;
          let shapes=`<rect width="${w}" height="${d}" fill="#f3efe5" stroke="#b9aa8a"/>`;
          if(plan.type==='panels')for(const p of plan.pieces)shapes+=`<rect x="${p.x}" y="${p.y}" width="${p.axis==='x'?p.length:p.thickness}" height="${p.axis==='y'?p.length:p.thickness}" fill="#9d7d50"/>`;
          if(plan.type==='gridfinity'){
            const [x,y]=plan.origin;
            for(let c=0;c<=plan.columns;c++)shapes+=`<path d="M ${x+c*42} ${y} v ${plan.grid_depth}" stroke="#b6c5b1" stroke-width="1"/>`;
            for(let r=0;r<=plan.rows;r++)shapes+=`<path d="M ${x} ${y+r*42} h ${plan.grid_width}" stroke="#b6c5b1" stroke-width="1"/>`;
            plan.bins.forEach((b,index)=>{shapes+=`<rect x="${b.px}" y="${b.py}" width="${b.width}" height="${b.depth}" fill="#d6e4d1" stroke="#46704b" stroke-width="2"/><text x="${b.px+b.width/2}" y="${b.py+b.depth/2}" text-anchor="middle" dominant-baseline="middle" font-size="14">${index+1}</text>`;});
          }
          return `<svg viewBox="-3 -3 ${w+6} ${d+6}" role="img" aria-label="Organizer top view. Front is at the top." style="display:block;width:100%;max-height:240px;margin:10px 0">${shapes}</svg><p class="hint">Top view &middot; front at top</p>`;
        }
        function organizerCards(item,i,s){
          return `<details class="help-details" ${item.organizers?.some(o=>o.type!=='none')?'open':''}><summary>Drawer organizers</summary><p class="hint">Drawer 1 is the bottom drawer. Each drawer can use a different organizer. Fit uses the actual box interior, including runner and stock deductions.</p>${Array.from({length:Math.min(8,Number(item.drawers)||1)},(_,j)=>{
            const o=organizerAt(i,s,j),args=`${i},${s},${j}`,fit=organizerFits[organizerKey(i,s,j)];
            const select=(key,label,options)=>`<div><label>${label}</label><select aria-label="${label}" onchange="changeOrganizer(${args},'${key}',this.value)">${options.map(([value,text])=>`<option value="${value}" ${o[key]===value?'selected':''}>${text}</option>`).join('')}</select></div>`;
            const field=(key,label,min,max,step=1,text=false)=>`<div><label>${label}</label><input aria-label="${label}" type="${text?'text':'number'}" ${text?'':`required min="${min}" max="${max}" step="${step}"`} value="${escapeHtml(o[key])}" onchange="changeOrganizer(${args},'${key}',this.value)"></div>`;
            return `<div class="stack-item"><strong>Drawer ${j+1} &middot; ${j===0?'bottom':j===Number(item.drawers)-1?'top':'middle'}</strong>${select('type','Organizer',[['none','None'],['panels','Panel dividers'],['gridfinity','Gridfinity']])}${o.type==='none'?'':`<div class="grid two">${field('clearance','Edge clearance (mm)',0,5,0.1)}${o.type==='panels'?`${select('layout','Panel layout',[['front_back','Front-to-back'],['side_side','Side-to-side'],['grid','Grid']])}${field('thickness','Divider thickness (mm)',3,18,0.1)}${field('material','Divider material',0,0,1,true)}${field('height','Divider height (0 = auto)',0,500,1)}${o.layout!=='side_side'?field('columns','Left-to-right ratios',0,0,1,true):''}${o.layout!=='front_back'?field('rows','Front-to-back ratios',0,0,1,true):''}`:select('align','Grid position',[['center','Center'],['front_left','Front left']])}</div>
            <p class="hint">${o.type==='panels'?'Ratios such as 1 2 1 describe clear compartments. Auto height leaves 10 mm above. Grid crossings use half-lap slots; fit slots to actual sheet thickness. No grooves are cut into the drawer.':'42 mm grid. Preview envelopes only: no mating profiles or printable STL. Heights use 7 mm units, a 3.8 mm lip allowance and a conservative 5 mm baseplate allowance. Column 1 / row 1 is front left.'}</p>
            ${o.type==='gridfinity'?`${o.bins.map((bin,index)=>`<div class="stack-item"><div class="stack-head"><strong>Bin ${index+1}</strong><button type="button" onclick="removeOrganizerBin(${args},${index})">Remove</button></div><div class="grid two">${[['x','Column'],['y','Row'],['w','Width (cells)'],['d','Depth (cells)'],['h','Height (7 mm units)']].map(([key,label])=>`<div><label>${label}</label><input type="number" required min="1" max="${key==='h'?60:120}" value="${escapeHtml(bin[key])}" aria-label="Bin ${index+1} ${label}" onchange="changeOrganizerBin(${args},${index},'${key}',this.value)"></div>`).join('')}</div></div>`).join('')}<button type="button" onclick="addOrganizerBin(${args})">+ Add bin</button>`:''}
            <button type="button" onclick="requestOrganizerPreview()">Update fit preview</button>${fit?`<p class="hint">Inside: ${fit.width.toFixed(1)} x ${fit.depth.toFixed(1)} x ${fit.height.toFixed(1)} mm${fit.type==='gridfinity'?` &middot; ${fit.columns} x ${fit.rows} cells &middot; max ${fit.max_height_units}u<br>Edge gaps L/R/F/B: ${fit.edge_gaps.map(v=>v.toFixed(1)).join(' / ')} mm`:''}</p>${organizerDiagram(fit)}`:'<p class="hint">Update fit after changing cabinet dimensions or organizer settings.</p>'}`}
            ${Number(item.drawers)>1?`<button type="button" class="ghost" onclick="copyOrganizer(${args})">Apply to all drawers in this section</button>`:''}</div>`;
          }).join('')}</details>`;
        }
        function counts(item,action){
          return `${item.kind==='drawer'?`<div><label>Drawers</label><input type="number" required min="1" max="8" value="${item.drawers}" aria-label="Drawer count" onchange="${action.replace('KEY','drawers')}"></div>`:item.kind==='door'?`<div><label>Doors side by side</label><select aria-label="Door count" onchange="${action.replace('KEY','doors')}"><option value="1" ${item.doors==1?'selected':''}>1 door</option><option value="2" ${item.doors==2?'selected':''}>2 doors</option></select></div>`:''}
          ${item.kind!=='drawer'?`<div><label>Shelves inside</label><input type="number" required min="0" max="8" value="${item.shelves}" aria-label="Shelf count" onchange="${action.replace('KEY','shelves')}"></div>`:''}`;
        }
        function renderSections(b,i){
          if(b.kind!=='stack')return '';
          const total=b.sections.reduce((sum,section)=>sum+(Number(section.weight)||0),0)||1;
          const ordered=b.sections.map((section,j)=>({section,j})).reverse();
          const percent=section=>Math.round((Number(section.weight)||0)*100/total);
          const preview=`<div class="cabinet-preview" role="img" aria-label="Bay ${i+1}, top to bottom: ${ordered.map(({section})=>kindNames[section.kind]).join(', ')}">${ordered.map(({section})=>`<div class="preview-cell ${section.kind}" style="flex:${Number(section.weight)||1}"><strong>${kindNames[section.kind]}</strong><span>${percent(section)}%</span></div>`).join('')}</div>`;
          const cards=ordered.map(({section,j},displayIndex)=>`<div class="stack-item" id="section-${i}-${j}"><div class="stack-head"><div><span class="position-tag">${j===b.sections.length-1?'Top':j===0?'Bottom':'Middle'}</span><span class="stack-title">${kindNames[section.kind]}</span></div><div class="stack-actions">
            <button type="button" aria-label="Move section up" title="Move up" onclick="moveSection(${i},${j},1)" ${j===b.sections.length-1?'disabled':''}>&uarr;</button>
            <button type="button" aria-label="Move section down" title="Move down" onclick="moveSection(${i},${j},-1)" ${j===0?'disabled':''}>&darr;</button>
            <button type="button" aria-label="Remove section" title="Remove section" onclick="removeSection(${i},${j})" ${b.sections.length<=2?'disabled':''}>&times;</button></div></div>
            ${typePicker(section.kind,`changeSection(${i},${j},'kind','VALUE')`)}
            <div class="stack-grid"><div><div class="share-line"><label>Height ratio</label><span class="share-badge">${percent(section)}% of height</span></div><input type="number" aria-label="Section height ratio" required min="0.2" max="10" step="0.1" value="${escapeHtml(section.weight)}" onchange="changeSection(${i},${j},'weight',this.value);refreshLayout()"></div>
            ${counts(section,`changeSection(${i},${j},'KEY',this.value)`)}</div>${section.kind==='drawer'?organizerCards(section,i,j):''}</div>`).join('');
          return `<div class="layout-tools"><span>Quick layout</span><button type="button" class="preset" onclick="layoutPreset(${i},'drawer')">Drawer + doors</button><button type="button" class="preset" onclick="layoutPreset(${i},'equal')">Equal split</button><button type="button" class="preset" onclick="layoutPreset(${i},'three')">3 sections</button></div><p class="section-intro">Shown top to bottom, like your cabinet. Height ratios share the available space; divider panels are automatic.</p><div class="section-layout">${preview}<div><button type="button" class="add-section" onclick="addSection(${i})" ${b.sections.length>=6?'disabled':''}>+ Add section above</button><div style="height:10px"></div>${cards}</div></div>`;
        }
        function renderBays(){
          const total=bays.reduce((sum,bay)=>sum+(Number(bay.weight)||0),0)||1;
          document.getElementById('bays').innerHTML=bays.map((b,i)=>`<div class="bay"><div class="bayhead"><div>Bay ${i+1}<div class="bay-subtitle">${bays.length===1?'Full cabinet width':i===0?'Left':i===bays.length-1?'Right':'Middle'} &middot; ${Math.round((Number(b.weight)||0)*100/total)}% of width</div></div><div class="stack-actions"><button type="button" aria-label="Move bay up / left" title="Move up / left" onclick="moveBay(${i},-1)" ${i===0?'disabled':''}>&uarr;</button><button type="button" aria-label="Move bay down / right" title="Move down / right" onclick="moveBay(${i},1)" ${i===bays.length-1?'disabled':''}>&darr;</button><button class="ghost remove" onclick="removeBay(${i})" type="button" ${bays.length<=1?'disabled':''}>Remove bay</button></div></div>
            ${typePicker(b.kind,`changeBay(${i},'kind','VALUE')`,true)}
            ${bays.length>1?`<div class="bay-width"><label>Width ratio</label><input type="number" aria-label="Bay width ratio" required min="0.2" max="10" step="0.1" value="${escapeHtml(b.weight)}" onchange="changeBay(${i},'weight',this.value);refreshLayout()"><span>Equal values give equal widths.</span></div>`:''}
            ${b.kind==='stack'?renderSections(b,i):`<div class="stack-grid">${counts(b,`changeBay(${i},'KEY',this.value)`)}</div>${b.kind==='drawer'?organizerCards(b,i,-1):''}<p class="hint">Need drawers below doors? Choose Mixed layout above.</p>`}</div>`).join('');
          updateSummary();
        }
        const tabOrder=['size','layout','build','base','worktop'];
        function showTab(key){
          if(!tabOrder.includes(key))return;
          for(const id of tabOrder){
            document.getElementById('panel-'+id).hidden=id!==key;
            const tab=document.getElementById('tab-'+id);tab.setAttribute('aria-selected',String(id===key));tab.tabIndex=id===key?0:-1;
          }
        }
        function revealInput(input){
          const panel=input.closest('[data-panel]');if(panel)showTab(panel.dataset.panel);
          let parent=input.parentElement;while(parent){if(parent.tagName==='DETAILS')parent.open=true;parent=parent.parentElement;}
          input.focus();input.scrollIntoView({block:'center',behavior:'smooth'});
        }
        function updateSummary(){
          const value=id=>document.getElementById(id).value;
          const worktop=document.getElementById('worktop').checked?` / ${value('worktop_thickness')} mm worktop included`:'';
          document.getElementById('editor-summary').textContent=`${value('width')} W \u00d7 ${value('height')} H \u00d7 ${value('depth')} D mm \u00b7 ${bays.length} ${bays.length===1?'bay':'bays'} \u00b7 ${value('style')}${worktop}`;
        }
        document.addEventListener('input',updateSummary);
        document.addEventListener('change',updateSummary);
        document.addEventListener('change',event=>{if(event.target.id==='toe')updateToeKick();});
        document.addEventListener('keydown',event=>{
          const tab=event.target.closest('[data-tab]');if(!tab||!['ArrowLeft','ArrowRight','Home','End'].includes(event.key))return;
          event.preventDefault();let index=tabOrder.indexOf(tab.dataset.tab);
          index=event.key==='Home'?0:event.key==='End'?tabOrder.length-1:(index+(event.key==='ArrowRight'?1:-1)+tabOrder.length)%tabOrder.length;
          showTab(tabOrder[index]);document.getElementById('tab-'+tabOrder[index]).focus();
        });
        const limits={caster_height:[35,400],caster_diameter:[20,250],caster_inset:[0,150],worktop_thickness:[6,100],worktop_front_overhang:[0,300],worktop_rear_overhang:[0,300],worktop_left_overhang:[0,300],worktop_right_overhang:[0,300],drawer_height_limit:[25,3000],drawer_rear_gap:[3,50],width:[300,5000],height:[100,3500],depth:[250,5000],panel:[9,36],back:[3,24],front:[9,32],toe:[0,250],timber_height:[20,200],timber_thickness:[10,100],frame_width:[25,90],frame_depth:[12,36],gap:[1,6],rail_width:[40,200],drawer_thickness:[6,30],drawer_bottom:[3,24]};
        for(const [id,[min,max]] of Object.entries(limits)){const input=document.getElementById(id);input.min=min;input.max=max;input.required=true;input.title=`Allowed range: ${min}-${max} mm`;}
        document.addEventListener('wheel',event=>{if(document.activeElement?.type==='number')document.activeElement.blur();},{passive:true});
        function showError(message){
          document.getElementById('error').textContent=message;
          if(!message)return;
          if(/worktop/i.test(message))showTab('worktop');
          else if(/toe kick|timber|caster|base/i.test(message))showTab('base');
          else if(/organizer|gridfinity|bay|section|height ratio|drawer front/i.test(message))showTab('layout');
          else if(/hardware|slide|stock|thickness|construction|rail|drawer height limit/i.test(message))showTab('build');
        }
        function collectConfig(){
          showError('');
          for(const input of document.querySelectorAll('input[type=number]')){
            if(input.disabled)continue;
            if(input.value.trim()===''||!input.checkValidity()){
              const label=input.id?document.querySelector(`label[for="${input.id}"]`)?.textContent:input.parentElement.querySelector('label')?.textContent;
              showError(`${label||'Number'}: enter a value from ${input.min} to ${input.max}. Current value: ${input.value||'empty'}.`);revealInput(input);return;
            }
          }
          const c={}; for(const id of ids) c[id]=['name','style','top_construction','bottom_construction','back_construction','drawer_slide','drawer_height_mode','worktop_material','base_type'].includes(id)?document.getElementById(id).value:n(document.getElementById(id).value);
          c.caster_front_brakes=document.getElementById('caster_front_brakes').checked;
          c.worktop=document.getElementById('worktop').checked;
          c.toe_frame=document.getElementById('toe_frame').checked;
          c.frame=document.getElementById('frame').checked;
          c.construction=document.querySelector('input[name=construction]:checked').value;
          c.bays=JSON.parse(JSON.stringify(frontBays));
          c.rear_bays=JSON.parse(JSON.stringify(rearBays));
          c.double_sided=document.getElementById('double_sided').checked;
          c.front_depth_share=Number(document.getElementById('front_depth_share').value);
          return c;
        }
        function submitConfig(){
          const c=collectConfig();if(!c)return;
          if(!window.sketchup || !window.sketchup.submit) return showError('This panel must be used inside SketchUp.');
          window.sketchup.submit(JSON.stringify(c));
        }
        document.addEventListener('change',()=>{organizerFits={};organizerRevision++;renderBays();});
        updateAccess();updateFrame();updateConstruction();updateDrawerHardware();updateWorktop();updateToeKick();renderBays();updateSummary();
      </script>
      </body>
      </html>
    HTML
  end

  unless file_loaded?(__FILE__)
    menu = UI.menu('Plugins').add_submenu('Kero Cabinet')
    @menu = menu
    menu.add_item('Create new cabinet...') { show_dialog }
    menu.add_item('Edit selected cabinet...') { edit_selected }
    menu.add_separator
    menu.add_item('Check for updates...') { Updater.check }
    menu.add_item('Update settings...') { Updater.show_settings }
    Updater.startup_check
    UI.add_context_menu_handler do |menu_context|
      item = selected_cabinet
      if item
        menu_context.add_separator
        menu_context.add_item('Kero Cabinet | Edit parameters') { show_dialog(item) }
      end
    end
    file_loaded(__FILE__)
  end
  # Older live sessions did not retain their submenu. Add a root command once
  # during the transition; subsequent reloads keep the same registration.
  if defined?(UI) && UI.respond_to?(:menu) && !@reload_command_registered
    reload_menu = @menu || UI.menu('Plugins')
    reload_menu.add_item(@menu ? 'Reload plugin now...' : 'Kero Cabinet | Reload plugin now...') { Updater.reload_from_menu }
    @reload_command_registered = true
  end

  if defined?(UI) && UI.respond_to?(:menu) && !@worktop_commands_registered
    worktop_menu = @menu || UI.menu('Plugins')
    worktop_menu.add_item(@menu ? 'Create worktop from selection...' : 'Kero Cabinet | Create worktop from selection...') { show_worktop_editor }
    worktop_menu.add_item(@menu ? 'Edit selected worktop...' : 'Kero Cabinet | Edit selected worktop...') { edit_selected_worktop }
    @worktop_commands_registered = true
  end

  if defined?(UI) && UI.respond_to?(:menu) && !@linked_commands_registered
    linked_menu = @menu || UI.menu('Plugins')
    linked_menu.add_item(@menu ? 'Create linked copy' : 'Kero Cabinet | Create linked copy') { linked_copy_command }
    linked_menu.add_item(@menu ? 'Make independent' : 'Kero Cabinet | Make independent') { independent_copy_command }
    if UI.respond_to?(:add_context_menu_handler)
      UI.add_context_menu_handler do |context_menu|
        selected = selected_cabinet
        if selected
          context_menu.add_separator
          context_menu.add_item('Kero Cabinet | Create linked copy') { linked_copy_command }
          context_menu.add_item('Kero Cabinet | Make independent') { independent_copy_command } if linked_cabinet?(selected)
        end
      end
    end
    @linked_commands_registered = true
  end

  if defined?(UI) && UI.respond_to?(:menu) && !@interior_command_registered
    interior_menu=@menu || UI.menu('Plugins')
    interior_menu.add_item(@menu ? 'Interior view...' : 'Kero Cabinet | Interior view...') { show_interior_view }
    if UI.respond_to?(:add_context_menu_handler)
      UI.add_context_menu_handler do |context_menu|
        cabinet=selected_cabinet
        context_menu.add_item('Kero Cabinet | Interior view...') { show_interior_view(cabinet) } if cabinet
      end
    end
    @interior_command_registered=true
  end

  if defined?(UI) && UI.respond_to?(:menu) && !@migration_command_registered
    migration_menu=@menu || UI.menu('Plugins')
    migration_menu.add_item(@menu ? 'Migrate all to current version...' : 'Kero Cabinet | Migrate all to current version...') { migrate_all_command }
    @migration_command_registered=true
  end

  # Read actual owned stock geometry; never regenerate the model for a report.
  def cutlist_container?(item)
    item.is_a?(Sketchup::ComponentInstance) || (defined?(Sketchup::Group) && item.is_a?(Sketchup::Group))
  end

  def cutlist_rows(scope, model=Sketchup.active_model)
    raise ArgumentError, 'Unknown cut list scope.' unless [:selected, :all].include?(scope)
    roots = scope == :selected ? model.selection.to_a : model.entities.to_a
    raise ArgumentError, 'Select Kero Cabinet objects or a group containing them first.' if roots.empty? && scope == :selected
    initial = scope == :selected && model.respond_to?(:edit_transform) ? model.edit_transform : Geom::Transformation.new
    grouped = {}
    walk = nil
    walk = lambda do |items, parent, path|
      items.each do |item|
        next unless cutlist_container?(item)
        definition = item.definition
        next if path.include?(definition)
        transform = parent * item.transformation
        name = item.get_attribute(DICT, 'part_name').to_s
        stock = definition.get_attribute(DICT, 'stock_key').to_s
        owned = !name.empty? && (!stock.empty? || definition.name.start_with?('KC | '))
        if owned
          material = item.material ? item.material.name : definition.name
          next if [material, definition.name, stock].any? { |text| text.match?(/hardware|caster-v1:/i) }
          bounds = definition.bounds
          raw = [bounds.width, bounds.height, bounds.depth].map(&:to_f)
          matrix = transform.to_a
          axes = 3.times.map { |axis| matrix[axis*4, 3] }
          scales = axes.map { |axis| Math.sqrt(axis.sum { |v| v*v }) }
          raise ArgumentError, "Collapsed part: #{name}. Restore its scale before exporting." if scales.any? { |scale| scale < 1e-9 }
          3.times do |a|
            ((a+1)...3).each do |b|
              dot = axes[a].zip(axes[b]).sum { |x,y| x*y }
              raise ArgumentError, "Skewed part: #{name}. Remove skewed parent scaling before exporting." if dot.abs > scales[a]*scales[b]*1e-6
            end
          end
          thickness, width, length = raw.zip(scales).map { |size, scale| (size*scale*25.4).round(3) }.sort
          raise ArgumentError, "Invalid dimensions for #{name}." unless thickness > 0 && length.finite?
          key = [material, thickness, width, length]
          row = grouped[key] ||= {material: material, thickness: thickness, width: width, length: length, quantity: 0, names: []}
          row[:quantity] += 1
          row[:names] << name unless row[:names].include?(name)
        else
          walk.call(definition.entities.to_a, transform, path + [definition])
        end
      end
    end
    walk.call(roots, initial, [])
    grouped.values.sort_by { |row| [row[:material], row[:thickness], -row[:length], -row[:width]] }
  end

  def sheet_money(cents)
    return 'Not priced' if cents.nil?
    whole=(cents/100).to_s.reverse.gsub(/(\d{3})(?=\d)/,'\\1,').reverse
    "#{whole}.#{(cents%100).to_s.rjust(2,'0')}"
  end

  def sheet_price_cents(value)
    return nil if value.nil? || value.to_s.strip.empty?
    text=value.to_s.strip.tr(',','.')
    unless text.match?(/\A\d{1,9}(?:\.\d{1,2})?\z/)
      raise ArgumentError,'Sheet prices must be non-negative, with at most two decimals and no thousands separators.'
    end
    whole,fraction=text.split('.',2)
    whole.to_i*100+fraction.to_s.ljust(2,'0').to_i
  end

  def sheet_price_text(cents)
    cents.nil? ? nil : "#{cents/100}.#{(cents%100).to_s.rjust(2,'0')}"
  end

  def sheet_price_profile(material,thickness)
    JSON.generate([material,stock_number(thickness)])
  end

  def sheet_price_catalog_key(material,thickness,settings)
    dimensions=[settings['width'],settings['length']].sort.map { |v| format('%.3f',v) }
    JSON.generate([material,stock_number(thickness),*dimensions,settings['currency']])
  end

  def sheet_price_groups(rows)
    rows.select { |row| row[:material].match?(/\bsheet\b/i) }.map do |row|
      {key:sheet_price_profile(row[:material],row[:thickness]),material:row[:material],thickness:stock_number(row[:thickness])}
    end.uniq { |group| group[:key] }.sort_by { |group| [group[:thickness].to_f,group[:material]] }
  end

  # Some SketchUp preference backends re-evaluate quoted strings on read.
  # Base64 keeps serialized JSON quotes out of that native preference layer.
  def read_sheet_record(key,legacy_key=nil)
    raw=Sketchup.read_default('KeroCabinet',key,'')
    unless raw.nil? || raw.to_s.empty?
      raise ArgumentError,'Unrecognized sheet preference format.' unless raw.is_a?(String) && raw.start_with?('KCJSON1:')
      return JSON.parse(Base64.strict_decode64(raw.delete_prefix('KCJSON1:')))
    end
    return nil unless legacy_key
    begin
      legacy=Sketchup.read_default('KeroCabinet',legacy_key,'')
      return nil if legacy.nil? || legacy.to_s.empty?
      JSON.parse(legacy)
    rescue SyntaxError,StandardError
      nil
    end
  end

  def write_sheet_record(key,value)
    encoded='KCJSON1:'+Base64.strict_encode64(JSON.generate(value))
    success=Sketchup.write_default('KeroCabinet',key,encoded)
    unless success && Sketchup.read_default('KeroCabinet',key,'')==encoded
      raise ArgumentError,'Sheet preferences could not be saved. Prices have not been confirmed as remembered. Check SketchUp preference access and retry.'
    end
    value
  end

  def read_sheet_price_catalog
    value=read_sheet_record('sheet_prices_v2','sheet_prices_v1')
    return {} if value.nil?
    raise ArgumentError,'Saved sheet price catalog is invalid.' unless value.is_a?(Hash)
    value.each_with_object({}) do |(key,price),catalog|
      next unless key.is_a?(String) && key.length<=500
      begin
        normalized=sheet_price_text(sheet_price_cents(price))
        catalog[key]=normalized unless normalized.nil?
      rescue ArgumentError
        next
      end
    end
  end

  def save_sheet_price_catalog(rows,settings,catalog,edits={})
    updated=catalog.dup
    raise ArgumentError,'Invalid pending sheet prices.' unless edits.is_a?(Hash) && edits.length<=1000
    allowed=sheet_price_groups(rows).map { |group| group[:key] }
    edits.each do |key,value|
      begin
        raise ArgumentError unless key.is_a?(String) && key.length<=500
        profile=JSON.parse(key)
        raise ArgumentError unless profile.is_a?(Array) && profile.length==5 && profile.all? { |part| part.is_a?(String) }
        material,thickness,width,length,currency=profile
        raise ArgumentError unless allowed.include?(sheet_price_profile(material,Float(thickness)))
        raise ArgumentError unless %w[TRY EUR USD].include?(currency)
        dimensions=[Float(width),Float(length)]
        raise ArgumentError unless dimensions.all? { |v| v.finite? && v.between?(100,10000) } && dimensions==dimensions.sort
        normalized_key=sheet_price_catalog_key(material,Float(thickness),{'width'=>dimensions[0],'length'=>dimensions[1],'currency'=>currency})
        raise ArgumentError unless normalized_key==key
        normalized=sheet_price_text(sheet_price_cents(value))
        normalized.nil? ? updated.delete(key) : updated[key]=normalized
      rescue JSON::ParserError,TypeError,ArgumentError
        raise ArgumentError,'Invalid pending sheet price. Use non-negative prices with up to two decimals.'
      end
    end
    sheet_price_groups(rows).each do |group|
      key=sheet_price_catalog_key(group[:material],group[:thickness],settings)
      value=settings['prices'][group[:key]]
      value.nil? ? updated.delete(key) : updated[key]=value
    end
    write_sheet_record('sheet_prices_v2',updated)
    updated
  end

  def sheet_group_cost(plan,group)
    key=sheet_price_profile(group[:material],group[:thickness])
    price=sheet_price_cents((plan[:settings]['prices']||{})[key])
    sheets=group[:sheets].length
    {unit_cents:price,total_cents:price.nil? ? 0 : price*sheets,unpriced_sheets:price.nil? ? sheets : 0}
  end

  def sheet_cost_html(plan)
    return '' if plan[:groups].empty?
    require 'cgi'
    currency=plan[:settings]['currency']||'TRY'
    costs=plan[:groups].map { |group| [group,sheet_group_cost(plan,group)] }
    missing=costs.sum { |_group,cost| cost[:unpriced_sheets] }
    total=costs.sum { |_group,cost| cost[:total_cents] }
    oversized=plan[:groups].sum { |group| group[:oversize].length }
    body=costs.map do |group,cost|
      amount=cost[:unit_cents].nil? ? 'Not priced' : sheet_money(cost[:total_cents])
      cells=[group[:material],"#{cutlist_number(group[:thickness])} mm",group[:sheets].length,sheet_money(cost[:unit_cents]),amount]
      '<tr>'+cells.map { |cell| "<td>#{CGI.escapeHTML(cell.to_s)}</td>" }.join+'</tr>'
    end.join
    partial=missing>0 || oversized>0
    html=String.new("<h3>Sheet costs (#{currency})</h3><table class=\"sheet-summary\"><thead><tr><th>Material</th><th>Thickness</th><th>Sheets</th><th>Unit price</th><th>Sheet cost</th></tr></thead><tbody>#{body}</tbody><tfoot><tr><th colspan=\"4\">#{partial ? 'Known subtotal - INCOMPLETE' : 'Total sheet cost'}</th><th>#{sheet_money(total)}</th></tr></tfoot></table>")
    html << "<p class=\"layout-error\">#{missing} sheets have no unit price. The subtotal is incomplete.</p>" if missing>0
    html << "<p class=\"layout-error\">#{oversized} oversized parts are not fitted or costed. The subtotal is incomplete.</p>" if oversized>0
    html << '<p class="note">Cost = fitted whole-sheet count x entered price per sheet. Timber, hardware, machining, tax and delivery are not added separately. Prices are user inputs; no currency conversion is performed. Enter an all-in sheet price if needed.</p>'
    html
  end

  def sheet_defaults
    {'width'=>2100.0,'length'=>2800.0,'kerf'=>3.0,'edge'=>10.0,'rotate'=>true,'currency'=>'TRY','prices'=>{}}
  end

  def validate_sheet_settings(source)
    raise ArgumentError,'Invalid sheet settings.' unless source.is_a?(Hash)
    settings=sheet_defaults.merge(source)
    settings['currency']=settings['currency'].to_s.upcase
    raise ArgumentError,'Choose TRY, EUR or USD for sheet prices.' unless %w[TRY EUR USD].include?(settings['currency'])
    prices=settings['prices']
    raise ArgumentError,'Invalid sheet price list.' unless prices.is_a?(Hash) && prices.length<=1000
    settings['prices']=prices.each_with_object({}) do |(key,value),normalized|
      raise ArgumentError,'Invalid sheet price profile.' unless key.is_a?(String) && key.length<=300
      normalized[key]=sheet_price_text(sheet_price_cents(value))
    end

    {'width'=>[100,10000],'length'=>[100,10000],'kerf'=>[0,20],'edge'=>[0,100]}.each do |key,(low,high)|
      number_between!(settings,key,low,high)
    end
    unless [true,false].include?(settings['rotate'])
      raise ArgumentError,'Choose whether 90-degree rotation is allowed.'
    end
    if [settings['width'],settings['length']].min-2*settings['edge']<10
      raise ArgumentError,'Edge trim leaves less than 10 mm of usable sheet space.'
    end
    settings
  end

  # Non-overlapping guillotine rectangles. Kerf is reserved on the waste side.
  def pack_sheet_pieces(pieces,settings,order,split)
    w,h=settings['width']-2*settings['edge'],settings['length']-2*settings['edge']
    sorted=pieces.sort_by { |p| order==:area ? [-p[:w]*p[:h],-[p[:w],p[:h]].max,p[:id]] : [-[p[:w],p[:h]].max,-p[:w]*p[:h],p[:id]] }
    sheets=[]
    sorted.each do |piece|
      options=[[piece[:w],piece[:h],false]]
      options << [piece[:h],piece[:w],true] if settings['rotate'] && piece[:w]!=piece[:h]
      choices=[]
      sheets.each_with_index do |sheet,si|
        sheet[:free].each_with_index do |rect,ri|
          options.each do |pw,ph,rotated|
            next if pw>rect[:w]+1e-7 || ph>rect[:h]+1e-7
            score=[[rect[:w]-pw,rect[:h]-ph].min,rect[:w]*rect[:h]-pw*ph,si,ri,rotated ? 1 : 0]
            choices << [score,si,ri,pw,ph,rotated]
          end
        end
      end
      if choices.empty?
        sheets << {free:[{x:0.0,y:0.0,w:w,h:h}],pieces:[]}
        pw,ph,rotated=options.find { |a,b,_| a<=w+1e-7 && b<=h+1e-7 }
        choice=[nil,sheets.length-1,0,pw,ph,rotated]
      else
        choice=choices.min_by(&:first)
      end
      _,si,ri,pw,ph,rotated=choice
      sheet=sheets[si]
      rect=sheet[:free].delete_at(ri)
      sheet[:pieces] << piece.merge(x:rect[:x]+settings['edge'],y:rect[:y]+settings['edge'],w:pw,h:ph,rotated:rotated)
      rw,rh=rect[:w]-pw-settings['kerf'],rect[:h]-ph-settings['kerf']
      leftovers=if split==:vertical
        [{x:rect[:x]+pw+settings['kerf'],y:rect[:y],w:rw,h:rect[:h]},
         {x:rect[:x],y:rect[:y]+ph+settings['kerf'],w:pw,h:rh}]
      else
        [{x:rect[:x]+pw+settings['kerf'],y:rect[:y],w:rw,h:ph},
         {x:rect[:x],y:rect[:y]+ph+settings['kerf'],w:rect[:w],h:rh}]
      end
      sheet[:free].concat(leftovers.select { |r| r[:w]>1e-7 && r[:h]>1e-7 })
    end
    sheets
  end

  def sheet_layout(rows,source)
    settings=validate_sheet_settings(source)
    sheet_rows=rows.each_with_index.select { |row,_index| row[:material].match?(/\bsheet\b/i) }
    count=sheet_rows.sum { |row,_| row[:quantity] }
    raise ArgumentError,'More than 10000 sheet parts. Generate a selected-object report in smaller batches.' if count>10000
    groups=sheet_rows.group_by { |row,_| [row[:material],row[:thickness]] }.map do |(material,thickness),entries|
      pieces=entries.flat_map do |row,index|
        Array.new(row[:quantity]) { |copy| {id:"#{index+1}.#{copy+1}",row:index+1,w:row[:width],h:row[:length]} }
      end
      uw,uh=settings['width']-2*settings['edge'],settings['length']-2*settings['edge']
      fits,oversize=pieces.partition { |p| (p[:w]<=uw+1e-7 && p[:h]<=uh+1e-7) || (settings['rotate'] && p[:h]<=uw+1e-7 && p[:w]<=uh+1e-7) }
      candidates=[:area,:longest].product([:vertical,:horizontal]).map { |order,split| pack_sheet_pieces(fits,settings,order,split) }
      sheets=candidates.min_by { |list| [list.length,list.sum { |sheet| sheet[:free].length }] }
      area=fits.sum { |p| p[:w]*p[:h] }
      waste=sheets.empty? ? 0.0 : 100*(1-area/(sheets.length*settings['width']*settings['length']))
      {material:material,thickness:thickness,sheets:sheets,oversize:oversize,waste:waste,pieces:pieces.length}
    end
    {settings:settings,groups:groups,excluded:rows.reject { |row| row[:material].match?(/\bsheet\b/i) }.sum { |r| r[:quantity] }}
  end

  def sheet_usage_summary(plan)
    sheet_area=plan[:settings]['width']*plan[:settings]['length']
    plan[:groups].group_by { |group| group[:thickness].to_f }.sort_by(&:first).map do |thickness,groups|
      fitted_area=groups.sum { |group| group[:sheets].sum { |sheet| sheet[:pieces].sum { |piece| piece[:w]*piece[:h] } } }
      missing_area=groups.sum { |group| group[:oversize].sum { |piece| piece[:w]*piece[:h] } }
      sheets=groups.sum { |group| group[:sheets].length }
      {thickness:thickness,materials:groups.map { |group| group[:material] }.uniq.sort,
       pieces:groups.sum { |group| group[:pieces] },area_m2:(fitted_area+missing_area)/1_000_000.0,
       sheets:sheets,not_fitted:groups.sum { |group| group[:oversize].length },
       waste:sheets.zero? ? nil : 100*(1-fitted_area/(sheets*sheet_area)),
       cost_cents:groups.sum { |group| sheet_group_cost(plan,group)[:total_cents] },
       unpriced_sheets:groups.sum { |group| sheet_group_cost(plan,group)[:unpriced_sheets] }}
    end
  end

  def sheet_usage_html(plan)
    summary=sheet_usage_summary(plan)
    return '' if summary.empty?
    require 'cgi'
    body=summary.map do |row|
      cells=["#{cutlist_number(row[:thickness])} mm",row[:materials].join(' / '),row[:pieces],
        format('%.3f',row[:area_m2]),row[:sheets],row[:waste] ? "#{format('%.1f',row[:waste])}%" : '-',row[:not_fitted],(row[:unpriced_sheets]>0 || row[:not_fitted]>0) ? "#{sheet_money(row[:cost_cents])} (partial)" : sheet_money(row[:cost_cents])]
      '<tr>'+cells.map { |cell| "<td>#{CGI.escapeHTML(cell.to_s)}</td>" }.join+'</tr>'
    end.join
    totals=[summary.sum { |r| r[:pieces] },summary.sum { |r| r[:area_m2] },summary.sum { |r| r[:sheets] },summary.sum { |r| r[:not_fitted] }]
    <<~HTML
      <h3>Usage by thickness</h3><table class="sheet-summary"><thead><tr><th>Thickness</th><th>Materials</th><th>Parts</th><th>Net area (m&sup2;)</th><th>Sheets</th><th>Waste</th><th>Not fitted</th><th>Sheet cost (#{plan[:settings]['currency']||'TRY'})</th></tr></thead><tbody>#{body}</tbody><tfoot><tr><th colspan="2">Total</th><th>#{totals[0]}</th><th>#{format('%.3f',totals[1])}</th><th>#{totals[2]}</th><th>-</th><th>#{totals[3]}</th><th>#{sheet_money(summary.sum { |r| r[:cost_cents] })}#{summary.any? { |r| r[:unpriced_sheets]>0 || r[:not_fitted]>0 } ? ' (partial)' : ''}</th></tr></tfoot></table>
      <p class="note">Net area includes all requested sheet parts, including those not fitted. Sheet counts and waste cover fitted parts only. Materials remain packed separately; thickness totals do not combine their sheets. Timber is excluded.</p>
    HTML
  end

  def sheet_layout_html(plan)
    require 'cgi'
    escape=->(text) { CGI.escapeHTML(text.to_s) }
    settings=plan[:settings]
    total=plan[:groups].sum { |g| g[:sheets].length }
    missing=plan[:groups].sum { |g| g[:oversize].length }
    html=String.new("<section><h2>Sheet layout</h2><p><strong>#{total} sheets#{missing>0 ? ' for fitting pieces only - INCOMPLETE' : ''}</strong> &middot; #{cutlist_number(settings['width'])} x #{cutlist_number(settings['length'])} mm &middot; kerf #{cutlist_number(settings['kerf'])} mm &middot; edge trim #{cutlist_number(settings['edge'])} mm &middot; rotation #{settings['rotate'] ? 'allowed' : 'off'}</p>")
    html << sheet_usage_html(plan)
    html << sheet_cost_html(plan)
    html << '<p class="note">Guillotine placement heuristic; minimum sheet count is not guaranteed. Waste includes trim and kerf. Part labels refer to numbered cut-list rows. Rotation off aligns part Length with sheet Length; physical grain direction is not recorded. Non-sheet stock is excluded from sheet totals.</p>'
    html << "<p class=\"note\">#{plan[:excluded]} timber/non-sheet pieces remain in the cut list.</p>" if plan[:excluded]>0
    html << '<p>No sheet-material parts in this scope.</p>' if plan[:groups].empty?
    plan[:groups].each do |group|
      html << "<h3>#{escape.call(group[:material])} - #{cutlist_number(group[:thickness])} mm: #{group[:sheets].length} sheets / #{format('%.1f',group[:waste])}% waste for fitted parts</h3>"
      unless group[:oversize].empty?
        labels=group[:oversize].group_by { |p| p[:row] }.map { |row,parts| "Row #{row}: #{parts.length} pieces" }.join('; ')
        html << "<p class=\"layout-error\"><strong>Does not fit usable stock: #{escape.call(labels)}.</strong> Increase stock size, reduce edge trim or enable rotation. These pieces are NOT included in the sheet count.</p>"
      end
      group[:sheets].each_with_index do |sheet,index|
        w,h=settings['width'],settings['length']
        html << "<div class=\"sheet-plan\"><h4>Sheet #{index+1} - #{sheet[:pieces].length} pieces</h4><svg viewBox=\"-5 -5 #{w+10} #{h+10}\" role=\"img\" aria-label=\"Sheet #{index+1} placement\"><rect width=\"#{w}\" height=\"#{h}\" fill=\"#eee9df\" stroke=\"#444\" stroke-width=\"2\"/><rect x=\"#{settings['edge']}\" y=\"#{settings['edge']}\" width=\"#{w-2*settings['edge']}\" height=\"#{h-2*settings['edge']}\" fill=\"none\" stroke=\"#aaa\" stroke-dasharray=\"8 8\"/>"
        sheet[:pieces].each do |piece|
          label="#{piece[:row]}#{piece[:rotated] ? ' R' : ''}"
          font=[[piece[:w],piece[:h]].min*0.4,[w,h].max/65.0].min
          html << "<g><title>#{escape.call(piece[:id])}: #{cutlist_number(piece[:w])} x #{cutlist_number(piece[:h])} mm</title><rect x=\"#{piece[:x]}\" y=\"#{piece[:y]}\" width=\"#{piece[:w]}\" height=\"#{piece[:h]}\" fill=\"#cbdcc3\" stroke=\"#355e40\" stroke-width=\"1\"/><text x=\"#{piece[:x]+piece[:w]/2}\" y=\"#{piece[:y]+piece[:h]/2}\" text-anchor=\"middle\" dominant-baseline=\"middle\" font-size=\"#{font}\">#{label}</text></g>"
        end
        html << '</svg><p class="note">R = rotated 90 degrees. Placements are blank sizes, not CNC toolpaths.</p></div>'
      end
    end
    html+'</section>'
  end

  def sheet_setup_html(initial,groups=[],catalog={})
    values=JSON.generate({settings:initial,groups:groups,catalog:catalog}).gsub('</','<\\/')
    <<~HTML
      <!doctype html><html lang="en"><head><meta charset="utf-8"><style>body{font:14px -apple-system,Arial,sans-serif;padding:22px;background:#f5f6f1;color:#253b30}h1{font-size:21px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}label{display:block;font-size:12px;margin:6px 0}input[type=number],input[type=text],select{box-sizing:border-box;width:100%;padding:10px;border:1px solid #bdcbb7;border-radius:6px}button{padding:12px;background:#355e40;color:white;border:0;border-radius:6px;margin-top:18px;cursor:pointer}p{font-size:12px;line-height:1.5;color:#65705e}#error{color:#ae3429}</style></head><body>
      <h1>Sheet settings</h1><p>Set stock size before generating the cut list. These dimensions apply separately to each sheet material and thickness. Timber stays in the list but is excluded from sheet counts.</p>
      <form id="sheet-form"><div class="grid"><div><label for="width">Sheet width (mm)</label><input id="width" type="number" min="100" max="10000" step="any" required></div><div><label for="length">Sheet length (mm)</label><input id="length" type="number" min="100" max="10000" step="any" required></div><div><label for="kerf">Saw kerf (mm)</label><input id="kerf" type="number" min="0" max="20" step="any" required></div><div><label for="edge">Edge trim per side (mm)</label><input id="edge" type="number" min="0" max="100" step="any" required></div></div>
      <label><input id="rotate" type="checkbox"> Allow 90-degree rotation</label><p>Rotation off keeps cut-list Length along sheet Length; grain metadata is not stored. The layout is a placement estimate and may use more sheets than an optimal solution.</p><h2>Sheet prices</h2><label for="currency">Currency</label><select id="currency"><option value="TRY">TRY</option><option value="EUR">EUR</option><option value="USD">USD</option></select><div class="grid" id="sheet-prices"></div><p>Price per whole sheet, for each material/thickness and the stock size above. Prices are remembered for this size and currency after generating. Leave blank for Not priced; enter 0 explicitly for free stock. Use up to two decimals, with a dot or comma and no thousands separators. No currency conversion.</p><p id="error" role="alert"></p><button type="submit">Generate cut list and layout</button> <button type="button" onclick="window.sketchup.cancel_setup()">Cancel</button></form>
      <script>
      const payload=#{values};
      const initial=payload.settings,priceGroups=payload.groups,priceCatalog=payload.catalog;
      let activePriceKeys={},priceEdits={};
      for(const key of ['width','length','kerf','edge'])document.getElementById(key).value=initial[key];
      document.getElementById('rotate').checked=initial.rotate;
      document.getElementById('currency').value=initial.currency;
      function escapePrice(text){return String(text).split('&').join('&amp;').split('<').join('&lt;').split('>').join('&gt;').split('"').join('&quot;').split("'").join('&#39;');}
      function stockPriceKey(group){const dimensions=[Number(document.getElementById('width').value),Number(document.getElementById('length').value)].sort((a,b)=>a-b).map(n=>n.toFixed(3));return JSON.stringify([group.material,group.thickness,...dimensions,document.getElementById('currency').value]);}
      function renderSheetPrices(){
        priceGroups.forEach((group,i)=>{const input=document.getElementById('sheet-price-'+i);if(input&&activePriceKeys[group.key]){const key=activePriceKeys[group.key];if(input.value!==(priceCatalog[key]??''))priceEdits[key]=input.value;priceCatalog[key]=input.value;}});
        activePriceKeys={};
        document.getElementById('sheet-prices').innerHTML=priceGroups.map((group,i)=>{const key=stockPriceKey(group);activePriceKeys[group.key]=key;const value=priceCatalog[key]??'';return '<div><label for="sheet-price-'+i+'">'+escapePrice(group.material)+' / '+escapePrice(group.thickness)+' mm</label><input type="text" inputmode="decimal" maxlength="20" id="sheet-price-'+i+'" placeholder="Not priced" value="'+escapePrice(value)+'"></div>';}).join('')||'<p>No sheet materials in this scope.</p>';
      }
      for(const key of ['width','length','currency'])document.getElementById(key).addEventListener('change',renderSheetPrices);
      renderSheetPrices();
      document.getElementById('sheet-form').addEventListener('submit',event=>{event.preventDefault();const data={};for(const key of ['width','length','kerf','edge'])data[key]=Number(document.getElementById(key).value);data.rotate=document.getElementById('rotate').checked;data.currency=document.getElementById('currency').value;data.prices={};priceGroups.forEach((group,i)=>{const value=document.getElementById('sheet-price-'+i).value;data.prices[group.key]=value;const key=activePriceKeys[group.key];if(value!==(priceCatalog[key]??''))priceEdits[key]=value;});data.price_edits=priceEdits;window.sketchup.generate_layout(JSON.stringify(data));});
      function sheetError(message){document.getElementById('error').textContent=message;}
      </script></body></html>
    HTML
  end

  def show_sheet_setup(rows,scope)
    saved=read_sheet_record('sheet_settings_v2','sheet_settings')
    initial=validate_sheet_settings(saved || sheet_defaults)
    catalog=read_sheet_price_catalog
    groups=sheet_price_groups(rows)
    @sheet_setup_dialog.close if @sheet_setup_dialog && @sheet_setup_dialog.visible?
    dialog=UI::HtmlDialog.new(dialog_title:'Kero Cabinet | Sheet settings',preferences_key:'KeroCabinet.SheetSettings',scrollable:true,resizable:true,width:560,height:690,style:UI::HtmlDialog::STYLE_DIALOG)
    @sheet_setup_dialog=dialog
    dialog.set_html(sheet_setup_html(initial,groups,catalog))
    dialog.add_action_callback('cancel_setup') { |_context| dialog.close }
    dialog.add_action_callback('generate_layout') do |_context,raw|
      begin
        payload=JSON.parse(raw)
        edits=payload.delete('price_edits')||{}
        settings=validate_sheet_settings(payload)
        plan=sheet_layout(rows,settings)
        save_sheet_price_catalog(rows,settings,catalog,edits)
        write_sheet_record('sheet_settings_v2',settings)
        show_cutlist_report(rows,scope,plan)
        dialog.close
      rescue StandardError => e
        dialog.execute_script("sheetError(#{JSON.generate(e.message)})")
      end
    end
    @dialogs ||= []
    @dialogs << dialog
    dialog.set_on_closed { @dialogs.delete(dialog) }
    dialog.show
  end

  def cutlist_number(value)
    format('%.3f', value).sub(/\.?0+\z/, '')
  end

  def cutlist_csv(rows)
    require 'csv'
    safe = lambda do |value|
      text = value.to_s
      text.match?(/\A[\s]*[=+@-]|\A[\t\r\n]/) ? "'#{text}" : text
    end
    "\uFEFF" + CSV.generate(row_sep: "\r\n") do |csv|
      csv << ['Part names', 'Quantity', 'Length (mm)', 'Width (mm)', 'Thickness (mm)', 'Material']
      rows.each do |row|
        csv << [safe.call(row[:names].join(' / ')), row[:quantity], cutlist_number(row[:length]), cutlist_number(row[:width]), cutlist_number(row[:thickness]), safe.call(row[:material])]
      end
    end
  end

  def cutlist_html(rows, scope, layout=nil)
    require 'cgi'
    escape = ->(value) { CGI.escapeHTML(value.to_s) }
    count = rows.sum { |row| row[:quantity] }
    body = rows.each_with_index.map do |row,index|
      cells = ["#{index+1}. #{row[:names].join(' / ')}", row[:quantity], cutlist_number(row[:length]), cutlist_number(row[:width]), cutlist_number(row[:thickness]), row[:material]]
      '<tr>' + cells.map { |value| "<td>#{escape.call(value)}</td>" }.join + '</tr>'
    end.join
    <<~HTML
      <!doctype html><html><head><meta charset="utf-8"><title>Kero Cabinet Cut List</title>
      <style>body{font:14px -apple-system,Arial,sans-serif;color:#222;margin:24px;background:#f5f5f2}h1{font-size:24px;margin-bottom:8px}p{line-height:1.5}button{padding:10px 16px;cursor:pointer;margin:8px 8px 12px 0}table{width:100%;border-collapse:collapse;background:white}th,td{padding:10px;text-align:left;border-bottom:1px solid #ddd}th{background:#e5e8e1;position:sticky;top:0}.sheet-plan{background:white;padding:16px;margin:18px 0;break-inside:avoid;page-break-inside:avoid}.sheet-plan svg{display:block;width:100%;height:520px}.layout-error{color:#ae3429}.sheet-summary{font-size:12px}.sheet-summary td:nth-child(2){text-align:left;white-space:normal}.sheet-summary td:nth-child(n+3){text-align:right;white-space:nowrap}td:nth-child(n+2):nth-child(-n+5){text-align:right;white-space:nowrap}.note{color:#555;font-size:12px}@media print{button{display:none}body{margin:0;background:white}th{position:static}}</style></head><body>
      <h1>Cut list</h1><p>#{scope == :selected ? 'Selected Kero objects' : 'All Kero objects in this model'} &middot; #{count} pieces &middot; #{rows.length} sizes &middot; millimetres</p>
      <button onclick="window.sketchup.export_csv()">Save CSV...</button><button onclick="window.sketchup.print_report()">Print...</button><button onclick="window.sketchup.sheet_settings()">Change sheet settings...</button>
      <p class="note">Snapshot taken when the Cut list command started. Actual stock blank sizes; no edge banding deductions or physical grain metadata. Sheet layouts use the settings below. Hardware excluded. Length is the longest dimension. Hidden parts are included.</p>
      <table><thead><tr><th>Part names</th><th>Qty</th><th>Length</th><th>Width</th><th>Thickness</th><th>Material</th></tr></thead><tbody>#{body}</tbody></table>#{layout ? sheet_layout_html(layout) : ''}</body></html>
    HTML
  end

  def show_cutlist(scope)
    rows = cutlist_rows(scope)
    return UI.messagebox('No Kero Cabinet wood parts found in this scope.') if rows.empty?
    show_sheet_setup(rows,scope)
  rescue StandardError => error
    UI.messagebox("Could not create cut list: #{error.message}")
  end

  def show_cutlist_report(rows,scope,layout)
    @cutlist_dialog.close if @cutlist_dialog && @cutlist_dialog.visible?
    dialog = UI::HtmlDialog.new(dialog_title: 'Kero Cabinet | Cut list', preferences_key: 'KeroCabinetCutList', scrollable: true, resizable: true, width: 1000, height: 650, style: UI::HtmlDialog::STYLE_DIALOG)
    @cutlist_dialog = dialog
    @dialogs ||= []
    @dialogs << dialog
    dialog.set_on_closed { @dialogs.delete(dialog) }
    dialog.set_html(cutlist_html(rows, scope, layout))
    dialog.add_action_callback('sheet_settings') { |_context| show_sheet_setup(rows,scope) }
    dialog.add_action_callback('export_csv') do |_context|
      begin
        path = UI.savepanel('Save cut list CSV', nil, 'Kero_Cabinet_Cut_List.csv')
        next unless path
        path += '.csv' unless path.downcase.end_with?('.csv')
        File.open(path, 'wb') { |file| file.write(cutlist_csv(rows)) }
      rescue StandardError => error
        UI.messagebox("Could not save cut list: #{error.message}")
      end
    end
    dialog.add_action_callback('print_report') do |_context|
      begin
        require 'tmpdir'
        require 'securerandom'
        require 'uri'
        printable = cutlist_html(rows, scope, layout)
          .sub('<button onclick="window.sketchup.export_csv()">Save CSV...</button>', '')
          .sub('<button onclick="window.sketchup.sheet_settings()">Change sheet settings...</button>', '')
          .sub('window.sketchup.print_report()', 'window.print()')
        path = File.join(Dir.tmpdir, "kero-cutlist-#{SecureRandom.hex(8)}.html")
        File.write(path, printable, encoding: 'UTF-8')
        UI.openURL('file://' + URI::DEFAULT_PARSER.escape(path))
      rescue StandardError => error
        UI.messagebox("Could not open print view: #{error.message}")
      end
    end
    dialog.show
  rescue StandardError => error
    UI.messagebox("Could not create cut list: #{error.message}")
  end

  if defined?(UI) && UI.respond_to?(:menu) && !@cutlist_commands_registered
    cutlist_menu = @menu || UI.menu('Plugins')
    cutlist_menu.add_separator if cutlist_menu.respond_to?(:add_separator)
    cutlist_menu.add_item('Cut list from selection...') { show_cutlist(:selected) }
    cutlist_menu.add_item('Cut list from all Kero objects...') { show_cutlist(:all) }
    @cutlist_commands_registered = true
  end

end
