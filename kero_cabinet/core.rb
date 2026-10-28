# frozen_string_literal: true
# Kero Cabinet v0.8.4, SketchUp 2020+; all design inputs use millimetres.
require 'sketchup.rb'
require 'json'
require_relative 'updater'

module KeroCabinet
  extend self

  DICT = 'kero_cabinet'.freeze
  VERSION = '0.8.4'.freeze

  DEFAULT = {
    'name' => 'Parametric Cabinet',
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
    'toe' => 100,
    'toe_frame' => true,
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

  def show_dialog(instance = nil)
    config = clone_defaults
    if instance && instance.valid?
      raw = instance.get_attribute(DICT, 'config')
      if raw.is_a?(String)
        stored = JSON.parse(raw)
        config = clone_defaults.merge(stored)
        unless stored.key?('bottom_construction')
          config['bottom_construction'] = stored['construction'] == 'top_bottom_full' ? 'full' : 'between'
        end
      end
    end

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
    c['depth'] - (c['back_construction'] == 'full' ? c['back'] : 0) - overlay_projection(c)
  end

  def validate_config(source)
    raise ArgumentError, 'Invalid configuration data.' unless source.is_a?(Hash)
    c = clone_defaults.merge(source)
    c['name'] = c['name'].to_s.strip[0, 80]
    c['name'] = 'Parametric Cabinet' if c['name'].empty?
    {
      'width' => [300, 5000], 'height' => [350, 3500], 'depth' => [250, 1200],
      'rail_width' => [40, 200], 'drawer_thickness' => [6, 30],
      'drawer_height_limit' => [25, 3000], 'drawer_rear_gap' => [3, 50], 'drawer_bottom' => [3, 24], 'panel' => [9, 36], 'back' => [3, 24], 'front' => [9, 32],
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
    if c['top_construction'] == 'rails' || c['back_construction'] == 'rails'
      c['construction'] = 'sides_full'
    end
    unless source.key?('bottom_construction')
      c['bottom_construction'] = source['construction'] == 'top_bottom_full' ? 'full' : 'between'
    end
    unless %w[between full].include?(c['bottom_construction'])
      raise ArgumentError, 'Bottom construction must be between or full.'
    end
    c['toe_frame'] = (c['toe_frame'] == true)
    if c['toe_frame'] && c['toe'] > 0 && c['toe'] < c['timber_height']
      raise ArgumentError, 'Toe kick height must be at least the upright timber height, or disable the support frame.'
    end
    c['frame'] = (c['frame'] == true)
    c['style'] = c['style'].to_s
    raise ArgumentError, 'Door style must be inset or overlay.' unless %w[inset overlay].include?(c['style'])
    if c['toe'] + 2 * [c['panel'], (c['frame'] ? c['frame_width'] : 0)].max >= c['height']
      raise ArgumentError, 'Height is insufficient for the toe kick and top/bottom sections.'
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
    if c['back_construction'] == 'rails' && c['height'] - c['toe'] - 2 * c['panel'] <= 2 * c['rail_width']
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
    total = c['bays'].sum { |b| b['weight'] }
    widths = c['bays'].map { |b| c['width'] * b['weight'] / total }
    minimum = c['panel'] * 2 + (c['frame'] ? c['frame_width'] : 0) + 110
    raise ArgumentError, "Each bay must be at least #{minimum.round} mm wide. Increase the width or adjust the weights." if widths.any? { |w| w < minimum }
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
  end

  def materials(model)
    colors = {
      'Case' => [214, 179, 130],
      'Back panel' => [198, 168, 130],
      'Face frame' => [141, 99, 66],
      'Door / drawer front' => [183, 137, 93],
      'Drawer box' => [227, 204, 161],
      'Toe kick timber' => [196, 159, 106]
    }
    colors.each_with_object({}) do |(name, rgb), h|
      material_name = "KC | #{name}"
      material = model.materials[material_name] || model.materials.add(material_name)
      material.color = Sketchup::Color.new(*rgb)
      h[name] = material
    end
  end

  # Each individual wooden part is a solid SketchUp ComponentInstance.
  # OpenCutList reads components, not groups. Coordinates and dimensions use mm.
  # x = width, y = depth (front is y = 0), z = height.
  def box(entities, name, material_name, x, y, z, sx, sy, sz, palette)
    dims = [sx, sy, sz]
    return if dims.any? { |v| v <= 0.25 }

    model = Sketchup.active_model
    definition = model.definitions.add("KC | #{name}")
    dx, dy, dz = dims.map { |v| mm(v) }
    points = [
      [0, 0, 0], [dx, 0, 0],
      [dx, dy, 0], [0, dy, 0]
    ]
    face = definition.entities.add_face(points)
    raise "Could not create face: #{name}" unless face
    # SketchUp forcibly orients faces drawn on the component's Z=0 ground plane
    # downwards, regardless of vertex winding. pushpull follows the face normal.
    # Always reverse a downward-facing face before extruding a positive height.
    face.reverse! unless face.normal.samedirection?(Z_AXIS)
    face.pushpull(dz)
    definition.description = name

    origin = [x, y, z].map { |v| mm(v) }
    instance = entities.add_instance(definition, Geom::Transformation.new(origin))
    instance.name = name
    instance.material = palette[material_name]
    instance
  end

  def generate_parts(entities, c, model)
    w, h, d = c.values_at('width', 'height', 'depth')
    d = case_depth(c)
    t, bt, ft, toe = c.values_at('panel', 'back', 'front', 'toe')
    face_frame = c['frame']
    fw = face_frame ? c['frame_width'] : 0.0
    fd = face_frame ? c['frame_depth'] : 0.0
    g = c['gap']
    palette = materials(model)
    add = lambda do |name, material, x, y, z, sx, sy, sz|
      box(entities, name, material, x, y, z, sx, sy, sz, palette)
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
    if toe > 0
      recess = [65.0, (d-fd)/3.0].min
      add.call('Toe kick front', 'Case', 0, fd + recess, 0, w, t, toe)
    end

    bay_total = c['bays'].sum { |b| b['weight'] }
    bounds = [0.0]
    c['bays'].each { |bay| bounds << bounds.last + w * bay['weight'] / bay_total }
    bounds[-1] = w
    n = c['bays'].length

    generate_toe_frame(add, c, bounds, fd) if c['toe_frame'] && toe > 0

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
      raise ArgumentError, "Bay #{i+1}: available opening is too small." if front_width < 60 || front_height < (bay['kind'] == 'drawer' ? drawer_minimum(c) + drawer_vertical_allowance(c) : 100)

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
        minimum_section = section['kind'] == 'drawer' ? drawer_minimum(c) + drawer_vertical_allowance(c) : 100
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
          runner_left = undermount && face_frame ? opening_left : cavity_left
          runner_width = undermount && face_frame ? opening_right - opening_left : cavity_width
          dbx = runner_left + side_clearance
          dbw = runner_width - 2*side_clearance
          dby = undermount ? [fd + 3, front_y + ft + 3].max : [fd, front_y + ft + [g, 3.2].max].max
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
          box_lower = [z_front, cavity_bottom].max + lower_clearance
          box_upper = [z_front + cell, cavity_top].min - upper_clearance
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

  def build_cabinet(c, instance)
    model = Sketchup.active_model
    model.start_operation(instance ? 'Edit Kero Cabinet' : 'Create Kero Cabinet', true)
    begin
      if instance && instance.valid?
        raise 'The selected object is no longer available.' unless instance.is_a?(Sketchup::ComponentInstance)
        instance.make_unique
        definition = instance.definition
        definition.entities.clear!
      else
        definition = model.definitions.add(c['name'])
        instance = model.active_entities.add_instance(definition, Geom::Transformation.new)
      end
      generate_parts(definition.entities, c, model)
      definition.name = c['name']
      definition.description = "Kero Cabinet #{VERSION}, created from parameters in millimetres"
      instance.name = c['name']
      instance.set_attribute(DICT, 'config', JSON.generate(c))
      instance.set_attribute(DICT, 'version', VERSION)
      model.selection.clear
      model.selection.add(instance)
      model.commit_operation
    rescue StandardError
      model.abort_operation
      raise
    end
    instance
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
      </style>
      </head>
      <body>
      <header><h1>Kero Cabinet</h1><p>Parametric SketchUp cabinet builder - v0.8.4</p></header>
      <main>
        <section class="section">
          <h2>Case dimensions</h2>
          <div class="grid">
            <div><label for="name">Component name</label><input id="name" type="text" style="min-width:0"></div>
            <div><label for="width">Width (mm)</label><input id="width" type="number" step="1"></div>
            <div><label for="height">Height (mm)</label><input id="height" type="number" step="1"></div>
            <div><label for="depth">Overall depth (mm)</label><input id="depth" type="number" step="1"></div>
            <div><label for="panel">Case panel (mm)</label><input id="panel" type="number" step="1"></div>
            <div><label for="back">Back panel (mm)</label><input id="back" type="number" step="1"></div>
            <div><label for="front">Door/front thickness (mm)</label><input id="front" type="number" step="1"></div>
            <div><label for="gap">Front gap (mm)</label><input id="gap" type="number" step="0.5"></div>
          </div>
          <p class="hint">Depth includes the back and any overlay fronts. The case is shortened to keep the requested overall depth. Enter the total height including the toe kick.</p>
        </section>
        <section class="section">
          <h2>Toe kick</h2>
          <div class="grid two">
            <div><label for="toe">Toe kick height (mm)</label><input id="toe" type="number" step="1"></div>
          </div>
          <div class="check"><input id="toe_frame" type="checkbox"><label for="toe_frame">Create timber support frame</label></div>
          <div class="grid two" style="margin-top:10px">
            <div><label for="timber_height">Upright timber height (mm)</label><input id="timber_height" type="number" min="20" max="200"></div>
            <div><label for="timber_thickness">Timber thickness (mm)</label><input id="timber_thickness" type="number" min="10" max="100"></div>
          </div>
          <p class="hint">Default: 50 x 100 mm timber with 100 mm upright. Butt joints, full-width front/rear rails and cross rails at bay boundaries, with extra rails for spans over 600 mm. The front panel spans the full cabinet width. The frame sits behind the toe kick front; taller toe spaces receive legs. No frame is created at zero toe height.</p>
        </section>
        <section class="section">
          <h2>Top / Bottom / Back construction</h2>
          <div class="grid">
            <div><label for="top_construction">Top construction</label><select id="top_construction" onchange="updateConstruction()"><option value="full">Full panel</option><option value="rails">Support rails</option></select></div>
            <div><label for="bottom_construction">Bottom construction</label><select id="bottom_construction"><option value="between">Between sides</option><option value="full">Full width</option></select></div>
            <div><label for="back_construction">Back construction</label><select id="back_construction" onchange="updateConstruction()"><option value="full">Full panel</option><option value="rails">Support rails</option></select></div>
            <div><label for="rail_width">Rail width (mm)</label><input id="rail_width" type="number" min="40" max="200"></div>
          </div>
          <p class="hint">Support rails use the case material and thickness. Rails extend the sides to the cabinet top. A full-width bottom sits under the sides. With back rails, no external back thickness is deducted from the overall depth.</p>
          <h3>Top panel arrangement</h3>
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
          <p class="hint">Top arrangement is locked when support rails are selected. Bottom construction stays independent. A full-width bottom raises the side start by its thickness without changing overall height.</p>
        </section>
        <section class="section">
          <h2>Face frame and door style</h2>
          <div class="grid two">
            <div><label for="style">Door placement</label><select id="style"><option value="inset">Inset</option><option value="overlay">Overlay</option></select></div>
            <div><label for="frame_width">Face frame width (mm)</label><input id="frame_width" type="number" step="1"></div>
            <div><label for="frame_depth">Face frame thickness (mm)</label><input id="frame_depth" type="number" step="1"></div>
          </div>
          <div class="check"><input id="frame" type="checkbox" onchange="updateFrame()"><label for="frame">Create face frame</label></div>
        </section>
        <section class="section">
          <h2>Drawer construction</h2>
          <div class="grid two" style="margin-bottom:12px">
            <div><label for="drawer_height_mode">Drawer box height</label><select id="drawer_height_mode" onchange="updateDrawerHardware()"><option value="fit">Fit available height</option><option value="limit">Limit height</option></select></div>
            <div><label for="drawer_height_limit">Maximum box height (mm)</label><input id="drawer_height_limit" type="number" min="25" max="3000" step="1"></div>
          </div>
          <p class="hint">Fit fills the available height after hardware clearances. Limit caps box height and still shrinks it to fit smaller openings. Front dimensions stay unchanged. Applies to all drawers.</p>
          <div style="margin-bottom:12px"><label for="drawer_slide">Drawer hardware</label><select id="drawer_slide" onchange="updateDrawerHardware()"><optgroup label="Side mount"><option value="side_48">Side mount - Easy-close / 47.7 mm min. box</option><option value="side_35">Side mount - Low-profile / 35.1 mm min. box</option></optgroup><optgroup label="Undermount"><option value="undermount_563h">Undermount - Blum TANDEM 563H reference</option></optgroup></select></div>
          <div style="margin-bottom:12px"><label for="undermount_length">Undermount drawer length (mm)</label><select id="undermount_length"><option value="0">Auto - longest fitting</option><option>229</option><option>305</option><option>381</option><option>457</option><option>533</option></select></div>
          <div style="margin-bottom:12px"><label for="drawer_rear_gap">Side-mount rear clearance (mm)</label><input id="drawer_rear_gap" type="number" min="3" max="50" step="1"></div>
          <p class="hint">Auto chooses the longest supported TANDEM length that fits. This reference supports up to 533 mm, so deeper cabinets can retain unused rear space. Saved manual lengths stay fixed; select Auto to recalculate.</p>
          <p id="hardware_hint" class="hint"></p>
          <div class="grid two">
            <div><label for="drawer_thickness">Drawer box thickness (mm)</label><input id="drawer_thickness" type="number" min="6" max="30"></div>
            <div><label for="drawer_bottom">Drawer bottom thickness (mm)</label><input id="drawer_bottom" type="number" min="3" max="24"></div>
          </div>
          <p class="hint">Box sides and front/back members share the box thickness. The bottom fits between them. Visible drawer fronts use Door/front thickness. Outer box width follows the selected slide side clearance. Shallow box heights adapt to the opening.</p>
        </section>
        <section class="section">
          <h2>Cabinet layout</h2>
          <p class="hint" style="margin:0 0 10px">Add bays from left to right. Choose their contents, then split a bay into stacked sections when you need drawers below doors.</p>
          <div id="bays"></div>
          <button class="ghost" onclick="addBay()" type="button">+ Add bay</button>
        </section>
      </main>
      <div class="actions"><span class="error" id="error"></span><span class="spacer"></span><button class="primary" type="button" onclick="submitConfig()">Create / update component</button></div>
      <script>
        const initial = /* INITIAL_CONFIG */ null;
        let bays = JSON.parse(JSON.stringify(initial.bays));
        const ids = ['name','width','height','depth','panel','back','front','toe','gap','style','frame_width','frame_depth','timber_height','timber_thickness','top_construction','bottom_construction','back_construction','rail_width','drawer_thickness','drawer_bottom','drawer_slide','undermount_length','drawer_rear_gap','drawer_height_mode','drawer_height_limit'];
        for (const id of ids) document.getElementById(id).value = initial[id];
        document.getElementById('frame').checked = !!initial.frame;
        document.getElementById('toe_frame').checked = !!initial.toe_frame;
        (document.querySelector('input[name=construction][value="'+(initial.construction||'sides_full')+'"]') || document.querySelector('input[name=construction][value=sides_full]')).checked = true;
        const n = (v) => Number(v);
        const escapeHtml = (s) => String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/"/g,'&quot;');
        function updateConstruction(){
          const rails=['top_construction','back_construction'].some(id=>document.getElementById(id).value==='rails');
          if(rails) document.querySelector('input[name=construction][value=sides_full]').checked=true;
          for(const radio of document.querySelectorAll('input[name=construction]')) radio.disabled=rails;
          document.getElementById('rail_width').disabled=!rails;
          document.getElementById('back').disabled=document.getElementById('back_construction').value==='rails';
        }
        function updateDrawerHardware(){
          document.getElementById('drawer_height_limit').disabled=document.getElementById('drawer_height_mode').value!=='limit';
          const under=document.getElementById('drawer_slide').value==='undermount_563h';
          document.getElementById('undermount_length').disabled=!under;
          document.getElementById('drawer_rear_gap').disabled=under;
          document.getElementById('hardware_hint').textContent=under?'TANDEM reference: 12-16 mm sides; inside width = opening minus 42 mm; 13 mm recessed bottom; 14 mm below and 6 mm above the box. Front/back members are raised to leave the underside open. Hook holes, exact rear notches, locking devices and hardware models are not generated; prepare them using the manufacturer template.':'Side-mount height and side-space references. Kero Cabinet reserves 4 mm above and below the box. Check actual length, width limits, mounting and holes against the hardware datasheet.';
        }
        function updateFrame(){
          for(const id of ['frame_width','frame_depth']) document.getElementById(id).disabled = !document.getElementById('frame').checked;
        }
        function addBay(){
          if(bays.length>=6) return showError('You can add up to 6 bays.');
          bays.push({kind:'door',weight:1,doors:1,drawers:4,shelves:1}); renderBays();
        }
        function removeBay(i){ if(bays.length>1){bays.splice(i,1);renderBays();} }
        function newSection(kind='door',weight=1){return {kind,weight,doors:1,drawers:1,shelves:1};}
        function changeBay(i,key,value){
          bays[i][key]=key==='kind'?value:Number(value);
          if(key==='kind'){
            if(value==='stack'&&!bays[i].sections)bays[i].sections=[newSection('drawer',1),newSection('door',3)];
            renderBays();
          }
        }
        function changeSection(i,j,key,value){bays[i].sections[j][key]=key==='kind'?value:Number(value);if(key==='kind')renderBays();}
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
            ${counts(section,`changeSection(${i},${j},'KEY',this.value)`)}</div></div>`).join('');
          return `<div class="layout-tools"><span>Quick layout</span><button type="button" class="preset" onclick="layoutPreset(${i},'drawer')">Drawer + doors</button><button type="button" class="preset" onclick="layoutPreset(${i},'equal')">Equal split</button><button type="button" class="preset" onclick="layoutPreset(${i},'three')">3 sections</button></div><p class="section-intro">Shown top to bottom, like your cabinet. Height ratios share the available space; divider panels are automatic.</p><div class="section-layout">${preview}<div><button type="button" class="add-section" onclick="addSection(${i})" ${b.sections.length>=6?'disabled':''}>+ Add section above</button><div style="height:10px"></div>${cards}</div></div>`;
        }
        function renderBays(){
          const total=bays.reduce((sum,bay)=>sum+(Number(bay.weight)||0),0)||1;
          document.getElementById('bays').innerHTML=bays.map((b,i)=>`<div class="bay"><div class="bayhead"><div>Bay ${i+1}<div class="bay-subtitle">${bays.length===1?'Full cabinet width':i===0?'Left':i===bays.length-1?'Right':'Middle'} &middot; ${Math.round((Number(b.weight)||0)*100/total)}% of width</div></div><button class="ghost remove" onclick="removeBay(${i})" type="button" ${bays.length<=1?'disabled':''}>Remove bay</button></div>
            ${typePicker(b.kind,`changeBay(${i},'kind','VALUE')`,true)}
            ${bays.length>1?`<div class="bay-width"><label>Width ratio</label><input type="number" aria-label="Bay width ratio" required min="0.2" max="10" step="0.1" value="${escapeHtml(b.weight)}" onchange="changeBay(${i},'weight',this.value);refreshLayout()"><span>Equal values give equal widths.</span></div>`:''}
            ${b.kind==='stack'?renderSections(b,i):`<div class="stack-grid">${counts(b,`changeBay(${i},'KEY',this.value)`)}</div><p class="hint">Need drawers below doors? Choose Mixed layout above.</p>`}</div>`).join('');
        }
        const limits={drawer_height_limit:[25,3000],drawer_rear_gap:[3,50],width:[300,5000],height:[350,3500],depth:[250,1200],panel:[9,36],back:[3,24],front:[9,32],toe:[0,250],timber_height:[20,200],timber_thickness:[10,100],frame_width:[25,90],frame_depth:[12,36],gap:[1,6],rail_width:[40,200],drawer_thickness:[6,30],drawer_bottom:[3,24]};
        for(const [id,[min,max]] of Object.entries(limits)){const input=document.getElementById(id);input.min=min;input.max=max;input.required=true;input.title=`Allowed range: ${min}-${max} mm`;}
        document.addEventListener('wheel',event=>{if(document.activeElement?.type==='number')document.activeElement.blur();},{passive:true});
        function showError(message){ document.getElementById('error').textContent=message; }
        function submitConfig(){
          showError('');
          for(const input of document.querySelectorAll('input[type=number]')){
            if(input.disabled)continue;
            if(input.value.trim()===''||!input.checkValidity()){
              const label=input.id?document.querySelector(`label[for="${input.id}"]`)?.textContent:input.parentElement.querySelector('label')?.textContent;
              showError(`${label||'Number'}: enter a value from ${input.min} to ${input.max}. Current value: ${input.value||'empty'}.`);input.focus();return;
            }
          }
          const c={}; for(const id of ids) c[id]=['name','style','top_construction','bottom_construction','back_construction','drawer_slide','drawer_height_mode'].includes(id)?document.getElementById(id).value:n(document.getElementById(id).value);
          c.toe_frame=document.getElementById('toe_frame').checked;
          c.frame=document.getElementById('frame').checked;
          c.construction=document.querySelector('input[name=construction]:checked').value;
          c.bays=JSON.parse(JSON.stringify(bays));
          if(!window.sketchup || !window.sketchup.submit) return showError('This panel must be used inside SketchUp.');
          window.sketchup.submit(JSON.stringify(c));
        }
        updateFrame();updateConstruction();updateDrawerHardware();renderBays();
      </script>
      </body>
      </html>
    HTML
  end

  unless file_loaded?(__FILE__)
    menu = UI.menu('Plugins').add_submenu('Kero Cabinet')
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
end
